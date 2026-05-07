import ballerina/http;
import ballerina/messaging;

// HTTP client for sending FHIR resources to the FHIR endpoint
final http:Client fhirClient = check new (fhirEndpointUrl);

// In-memory message store for failed messages (failure store)
final messaging:Store failureStore = new messaging:InMemoryMessageStore();

// In-memory message store for dead-letter messages (persistent failures)
final messaging:Store deadLetterStore = new messaging:InMemoryMessageStore();

// HTTP client for sending custom patient data to the backend
final http:Client customPatientClient = check new (customPatientEndpointUrl);
