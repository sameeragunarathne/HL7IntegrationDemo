import ballerina/log;
import ballerinax/health.hl7v2;

// Extracts the raw HL7 message string from MLLP-framed bytes.
// MLLP wraps messages with 0x0B (start) and 0x1C 0x0D (end).
function extractMllpPayload(byte[] data) returns string|error {
    int startIdx = 0;
    int endIdx = data.length();

    // Skip leading MLLP start block character (0x0B)
    if data.length() > 0 && data[0] == 0x0B {
        startIdx = 1;
    }

    // Trim trailing MLLP end block (0x1C) and carriage return (0x0D)
    if endIdx >= 2 && data[endIdx - 1] == 0x0D && data[endIdx - 2] == 0x1C {
        endIdx = endIdx - 2;
    } else if endIdx >= 1 && data[endIdx - 1] == 0x1C {
        endIdx = endIdx - 1;
    }

    byte[] payload = data.slice(startIdx, endIdx);
    return string:fromBytes(payload);
}

// Builds an MLLP acknowledgement (ACK) response for the given message control ID.
function buildMllpAck(string messageControlId, string ackCode) returns byte[]|error {
    string ackMessage = string `MSH|^~\&|FHIR_BRIDGE||SENDING_APP||${getCurrentTimestamp()}||ACK|${messageControlId}|P|2.7` + "\r" +
        string `MSA|${ackCode}|${messageControlId}` + "\r";
    byte[] ackBytes = ackMessage.toBytes();
    return hl7v2:createHL7WirePayload(ackBytes);
}

// Returns a simple timestamp string for ACK messages.
function getCurrentTimestamp() returns string {
    return "20240101120000";
}

// Logs a failure with context information.
function logFailure(string context, error err) {
    log:printError(string `[${context}] Error: ${err.message()}`, err);
}
