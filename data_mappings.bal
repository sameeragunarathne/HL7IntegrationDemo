import ballerinax/health.hl7v23;

// Maps an HL7v2.7 PID segment to the custom PatientRecord structure.
isolated function pidToCustomPatientRecord(hl7v23:PID pid) returns CustomPatientPayload => {
    patient_record: {
        internal_id: extractPatientId(pid),
        first_name: extractFirstName(pid),
        last_name: extractLastName(pid),
        date_of_birth: formatDob(pid.pid7.ts1),
        sex: pid.pid8,
        marital_status: pid.pid16,
        phone_mobile: extractMobilePhone(pid),
        email_address: extractEmail(pid),
        street_address: extractStreetAddress(pid),
        city: extractCity(pid),
        state_code: extractState(pid),
        postal_code: extractPostalCode(pid),
        country_code: extractCountry(pid),
        emergency_contact: ()
    }
};

// Extracts the primary patient identifier from PID-3.
isolated function extractPatientId(hl7v23:PID pid) returns string {
    hl7v23:CX[] identifiers = pid.pid3;
    if identifiers.length() > 0 {
        hl7v23:CX firstId = identifiers[0];
        return firstId.cx1;
    }
    return "";
}

// Extracts the given (first) name from PID-5.
isolated function extractFirstName(hl7v23:PID pid) returns string {
    hl7v23:XPN[] names = pid.pid5;
    if names.length() > 0 {
        hl7v23:XPN primaryName = names[0];
        return primaryName.xpn2;
    }
    return "";
}

// Extracts the family (last) name from PID-5.
isolated function extractLastName(hl7v23:PID pid) returns string {
    hl7v23:XPN[] names = pid.pid5;
    if names.length() > 0 {
        hl7v23:XPN primaryName = names[0];
        return primaryName.xpn1;
    }
    return "";
}

// Formats the DTM date of birth (YYYYMMDD) to ISO format (YYYY-MM-DD).
isolated function formatDob(string dtm) returns string {
    if dtm.length() >= 8 {
        string year = dtm.substring(0, 4);
        string month = dtm.substring(4, 6);
        string day = dtm.substring(6, 8);
        return string `${year}-${month}-${day}`;
    }
    return dtm;
}

// Extracts administrative sex code from PID-8 (CWE.1).
isolated function extractSex(hl7v23:PID pid) returns string {
    return pid.pid8;
}

// Extracts the mobile phone number from PID-13 (XTN).
// Prefers XTN.12 (unformatted), then constructs from country/area/local components.
isolated function extractMobilePhone(hl7v23:PID pid) returns string {
    hl7v23:XTN[] phones = pid.pid13;
    if phones.length() > 0 {
        hl7v23:XTN phone = phones[0];
        string localNum = phone.xtn7;
        if localNum.length() > 0 {
            string areaCode = phone.xtn6;
            string countryCode = phone.xtn5;
            if countryCode.length() > 0 && areaCode.length() > 0 {
                return string `+${countryCode}-${areaCode}-${localNum}`;
            } else if areaCode.length() > 0 {
                return string `${areaCode}-${localNum}`;
            }
            return localNum;
        }
    }
    return "";
}

// Extracts the email address from PID-13 (XTN.4 = communication address for email).
isolated function extractEmail(hl7v23:PID pid) returns string {
    hl7v23:XTN[] phones = pid.pid13;
    foreach hl7v23:XTN xtn in phones {
        // XTN.3 = "NET" indicates internet/email; XTN.4 holds the email address
        string equipType = xtn.xtn3;
        string commAddress = xtn.xtn4;
        if equipType == "NET" && commAddress.length() > 0 {
            return commAddress;
        }
    }
    return "";
}

// Extracts the street address from PID-11 (XAD.1.SAD.1).
isolated function extractStreetAddress(hl7v23:PID pid) returns string {
    hl7v23:XAD[] addresses = pid.pid11;
    if addresses.length() > 0 {
        hl7v23:XAD addr = addresses[0];
        return addr.xad1;
    }
    return "";
}

// Extracts the city from PID-11 (XAD.3).
isolated function extractCity(hl7v23:PID pid) returns string {
    hl7v23:XAD[] addresses = pid.pid11;
    if addresses.length() > 0 {
        hl7v23:XAD addr = addresses[0];
        return addr.xad3;
    }
    return "";
}

// Extracts the state code from PID-11 (XAD.4).
isolated function extractState(hl7v23:PID pid) returns string {
    hl7v23:XAD[] addresses = pid.pid11;
    if addresses.length() > 0 {
        hl7v23:XAD addr = addresses[0];
        return addr.xad4;
    }
    return "";
}

// Extracts the postal code from PID-11 (XAD.5).
isolated function extractPostalCode(hl7v23:PID pid) returns string {
    hl7v23:XAD[] addresses = pid.pid11;
    if addresses.length() > 0 {
        hl7v23:XAD addr = addresses[0];
        return addr.xad5;
    }
    return "";
}

// Extracts the country code from PID-11 (XAD.6).
isolated function extractCountry(hl7v23:PID pid) returns string {
    hl7v23:XAD[] addresses = pid.pid11;
    if addresses.length() > 0 {
        hl7v23:XAD addr = addresses[0];
        return addr.xad6;
    }
    return "";
}

