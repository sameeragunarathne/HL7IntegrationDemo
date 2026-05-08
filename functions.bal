import ballerina/log;
import ballerinax/health.hl7v2;
import ballerinax/health.hl7v23;

const byte MLLP_START = 0x0B;
const byte MLLP_END = 0x1C;
const byte MLLP_CR = 0x0D;

// Strips MLLP framing and returns plain HL7 string.
function extractHl7String(readonly & byte[] data) returns string|error {
    byte[] hl7Bytes = data;
    // Strip leading VT (0x0B) and trailing FS+CR (0x1C 0x0D)
    if data.length() > 3 && data[0] == MLLP_START {
        hl7Bytes = data.slice(1, data.length() - 2);
    } else if data.length() > 1 && data[data.length() - 1] == MLLP_END {
        hl7Bytes = data.slice(0, data.length() - 1);
    } else if data.length() > 2 && data[data.length() - 1] == MLLP_CR && data[data.length() - 2] == MLLP_END {
        hl7Bytes = data.slice(0, data.length() - 2);
    }
    return string:fromBytes(hl7Bytes);
}

function extractMessageControlId(readonly & byte[] data) returns string|error {
    hl7v2:Message parsedMessage = check hl7v2:parse(data);
    anydata mshSegment = parsedMessage["msh"];
    if mshSegment is () {
        return error("MSH segment not found in HL7 message");
    }
    hl7v23:MSH msh = check mshSegment.cloneWithType(hl7v23:MSH);
    if msh.msh10.length() == 0 {
        return error("MSH-10 message control ID not found in HL7 message");
    }
    return msh.msh10;
}

// Builds MLLP-framed HL7 ACK message.
function buildMllpAck(string originalControlId) returns byte[]|error {
    hl7v23:ACK ack = {
        msh: {
            msh2: "^~\\&",
            msh3: {hd1: "EHR-Integration"},
            msh4: {hd1: "WSO2"},
            msh5: {hd1: "CompuLink"},
            msh6: {hd1: "ClinicLink"},
            msh7: {ts1: "20260409120000"},
            msh9: {cm_msg1: "ACK"},
            msh10: "ACK-" + originalControlId,
            msh11: {pt1: "P"},
            msh12: "2.3"
        },
        msa: {
            msa1: "AA",
            msa2: originalControlId,
            msa3: "Message accepted and forwarded to Mosaic EMR"
        }
    };
    return hl7v2:encode(hl7v23:VERSION, ack);
}

// Logs a failure with context information.
function logFailure(string context, error err) {
    log:printError(string `[${context}] Error: ${err.message()}`, err);
}
