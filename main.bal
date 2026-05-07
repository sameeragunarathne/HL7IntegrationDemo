import ballerina/log;
import ballerina/tcp;
import xlibb/pipeline;

// MLLP TCP listener for receiving HL7 ADT messages
listener tcp:Listener mllpListener = check new (mllpListenerPort);

service on mllpListener {
    remote function onConnect(tcp:Caller caller) returns tcp:ConnectionService|tcp:Error? {
        log:printInfo(string `[MLLP] New connection from client`);
        return new MllpConnectionService(caller);
    }
}

// Handles each individual MLLP TCP connection
service class MllpConnectionService {
    *tcp:ConnectionService;

    private final tcp:Caller caller;

    function init(tcp:Caller caller) {
        self.caller = caller;
    }

    remote function onBytes(readonly & byte[] data) returns tcp:Error? {
        log:printDebug(string `[MLLP] Received HL7 message (${data.length()} bytes)`);

        // Submit the HL7 message to the pipeline asynchronously
        Hl7MessagePayload hl7Payload = {rawMessage: data};
        _ = start processHl7Message(hl7Payload);

        // Send MLLP ACK back to the sender
        byte[]|error ackBytes = buildMllpAck("ACK_CTRL_ID", "AA");
        if ackBytes is error {
            logFailure("MLLP ACK", ackBytes);
            return;
        }
        tcp:Error? sendResult = self.caller->writeBytes(ackBytes);
        if sendResult is tcp:Error {
            logFailure("MLLP ACK send", sendResult);
        }
    }

    remote function onError(tcp:Error err) {
        logFailure("MLLP connection", err);
    }

    remote function onClose() {
        log:printDebug("[MLLP] Connection closed");
    }
}

// Executes the ADT pipeline for the given HL7 message payload.
function processHl7Message(Hl7MessagePayload hl7Payload) {
    pipeline:ExecutionSuccess|pipeline:ExecutionError result = adtPipeline.execute(hl7Payload.clone());
    if result is pipeline:ExecutionError {
        log:printError(string `[Pipeline] Execution failed: ${result.message()}. Message stored for replay.`, result);
    } else {
        log:printInfo("[Pipeline] Message processed successfully");
    }
}
