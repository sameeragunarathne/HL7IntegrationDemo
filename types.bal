// Represents the raw HL7 message payload passed through the pipeline
type Hl7MessagePayload record {|
    byte[] rawMessage;
|};

// Represents the converted FHIR bundle JSON payload passed through the pipeline
type BackendPayload record {|
    json fhirBundle;
    byte[] rawMessage;
    CustomPatientPayload customPatientPayload?;
|};

// Emergency contact details for the custom patient payload
type EmergencyContact record {|
    string name;
    string relation;
    string phone;
|};

// Inner patient record for the custom patient payload
type PatientRecord record {|
    string internal_id;
    string first_name;
    string last_name;
    string date_of_birth;
    string sex;
    string marital_status;
    string phone_mobile;
    string email_address;
    string street_address;
    string city;
    string state_code;
    string postal_code;
    string country_code;
    EmergencyContact emergency_contact?;
|};

// Top-level custom patient payload
type CustomPatientPayload record {|
    PatientRecord patient_record;
|};

// Response returned when a failed message is fetched from the store
type FailedMessageInfo record {|
    string id;
    anydata payload;
|};

// Response for replay operations
type ReplayResponse record {|
    string message;
    string messageId?;
    string status?;
|};

// Response when no messages are available
type EmptyStoreResponse record {|
    string message;
|};
