import ballerina/http;
import ballerina/log;
import ballerinax/health.hl7v2;
import ballerinax/health.hl7v23 as _;
import ballerinax/health.hl7v23.utils.v2tofhirr4 as v2fhir;
import ballerinax/health.hl7v23;
import xlibb/pipeline;

// Pipeline transformer: parses the raw HL7 string and converts it to a FHIR bundle JSON.
@pipeline:TransformerConfig {id: "hl7ToFhirTransformer"}
isolated function hl7ToFhirTransformer(pipeline:MessageContext msgCtx) returns BackendPayload|error {
    Hl7MessagePayload hl7Payload = check msgCtx.getContentWithType();
    byte[] rawMessage = hl7Payload.rawMessage;

    hl7v2:Message parsedMessage = check hl7v2:parse(rawMessage);
    json|error fhirBundle = v2fhir:v2ToFhir(parsedMessage);
    if fhirBundle is json {
        log:printInfo("[Pipeline] HL7 message converted to FHIR bundle", fhirBundle = fhirBundle);
        return {
            fhirBundle: fhirBundle,
            rawMessage: rawMessage
        };
    } else {
        log:printError("Error occurred while transforming v2tofhir", fhirBundle);
        return fhirBundle;
    }
}

// Pipeline transformer: extracts custom patient payload from the original HL7 message.
@pipeline:TransformerConfig {id: "extractCustomPatientTransformer"}
isolated function extractCustomPatientTransformer(pipeline:MessageContext msgCtx) returns BackendPayload|error {
    BackendPayload backendPayload = check msgCtx.getContentWithType();
    byte[] rawMessage = backendPayload.rawMessage;
    hl7v2:Message parsedMessage = check hl7v2:parse(rawMessage);

    // Extract PID segment
    anydata pidSegment = parsedMessage["pid"];
    if pidSegment is () {
        log:printError("PID segment not found");
        return error("PID segment not found in HL7 message");
    }
    hl7v23:PID pid = check pidSegment.cloneWithType(hl7v23:PID);

    CustomPatientPayload patientPayload = pidToCustomPatientRecord(pid);
    return {
        fhirBundle: backendPayload.fhirBundle,
        rawMessage: backendPayload.rawMessage,
        customPatientPayload: patientPayload
    };
}

// Pipeline destination: sends the FHIR bundle to the configured FHIR endpoint.
@pipeline:DestinationConfig {
    id: "fhirEndpointDestination",
    retryConfig: {
        maxRetries: 3,
        retryInterval: 2
    }
}
isolated function fhirEndpointDestination(pipeline:MessageContext msgCtx) returns json|error {
    BackendPayload fhirPayload = check msgCtx.getContentWithType();
    json fhirBundle = fhirPayload.fhirBundle;

    http:Response response = check fhirClient->post("/", fhirBundle, mediaType = "application/fhir+json");
    int statusCode = response.statusCode;

    if statusCode >= 200 && statusCode < 300 {
        log:printInfo(string `[Pipeline] FHIR bundle sent successfully. Status: ${statusCode}`);
        json responseBody = check response.getJsonPayload();
        return responseBody;
    }

    string responseText = check response.getTextPayload();
    return error(string `FHIR endpoint returned error status ${statusCode}: ${responseText}`);
}

// Pipeline destination: extracts PID (and optionally NK1) from the HL7 message
// and sends the mapped custom patient payload to the configured backend.
@pipeline:DestinationConfig {
    id: "customPatientBackendDestination",
    retryConfig: {
        maxRetries: 3,
        retryInterval: 2
    }
}
isolated function customPatientBackendDestination(pipeline:MessageContext msgCtx) returns json|error {
    BackendPayload backendPayload = check msgCtx.getContentWithType();
    CustomPatientPayload? patientPayload = backendPayload.customPatientPayload;
    if patientPayload is () {
        log:printError("Custom patient payload not found in backend payload");
        return error("Custom patient payload not found in backend payload");
    }

    json payloadJson = patientPayload.toJson();
    log:printInfo("Mapped custom patient payload:", payload = payloadJson);

    http:Response response = check customPatientClient->post("/", payloadJson, mediaType = "application/json");
    int statusCode = response.statusCode;

    if statusCode >= 200 && statusCode < 300 {
        log:printInfo(string `[Pipeline] Custom patient data sent successfully. Status: ${statusCode}`);
        json responseBody = check response.getJsonPayload();
        return responseBody;
    }

    string responseText = check response.getTextPayload();
    return error(string `Custom patient endpoint returned error status ${statusCode}: ${responseText}`);
}

// The handler chain that orchestrates HL7-to-FHIR transformation and delivery with replay support.
final pipeline:HandlerChain adtPipeline = check new (
    name = "adtFhirPipeline",
    processors = [hl7ToFhirTransformer, extractCustomPatientTransformer],
    destinations = [fhirEndpointDestination, customPatientBackendDestination],
    failureStore = failureStore,
    replayListenerConfig = {
        pollingInterval: 10,
        maxRetries: 5,
        retryInterval: 5,
        deadLetterStore: deadLetterStore,
        replayStore: replayStore
    }
);
