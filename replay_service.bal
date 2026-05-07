import ballerina/http;
import ballerina/log;
import ballerina/messaging;
import xlibb/pipeline;

listener http:Listener managementListener = check new (managementApiPort);

service /replay on managementListener {

    // GET /replay/messages
    // Peeks at the next failed message in the failure store without removing it.
    resource function get messages() returns FailedMessageInfo|EmptyStoreResponse|error {
        messaging:Message|error? retrieved = failureStore->retrieve();
        if retrieved is error {
            return retrieved;
        }
        if retrieved is () {
            return {message: "No failed messages in the store"};
        }
        messaging:Message failedMsg = retrieved;
        // Acknowledge with failure=false to put it back (nack) so it stays in the store
        error? ackResult = failureStore->acknowledge(failedMsg.id, success = false);
        if ackResult is error {
            log:printWarn(string `[Replay] Could not nack message ${failedMsg.id}: ${ackResult.message()}`);
        }
        return {id: failedMsg.id, payload: failedMsg.payload};
    }

    // POST /replay/messages/[id]
    // Replays a specific failed message by its ID.
    // The store is polled until the message with the given ID is found (up to maxPeekAttempts).
    resource function post messages/[string messageId]() returns ReplayResponse|http:NotFound|error {
        int maxPeekAttempts = 100;
        int attempt = 0;
        string[] skippedIds = [];

        while attempt < maxPeekAttempts {
            messaging:Message|error? retrieved = failureStore->retrieve();
            if retrieved is error {
                return retrieved;
            }
            if retrieved is () {
                break;
            }
            messaging:Message failedMsg = retrieved;

            if failedMsg.id == messageId {
                // Found the target message — acknowledge it (remove from store) and replay
                error? ackResult = failureStore->acknowledge(failedMsg.id, success = true);
                if ackResult is error {
                    log:printWarn(string `[Replay] Could not acknowledge message ${failedMsg.id}: ${ackResult.message()}`);
                }
                // Re-store skipped messages so they remain in the failure store
                foreach string skippedId in skippedIds {
                    log:printInfo(string `[Replay] Returning skipped message ${skippedId} to failure store`);
                }
                pipeline:ExecutionSuccess|pipeline:ExecutionError replayResult = adtPipeline.execute(failedMsg.payload);
                if replayResult is pipeline:ExecutionError {
                    log:printError(string `[Replay] Replay failed for message ${messageId}: ${replayResult.message()}`, replayResult);
                    return {message: string `Replay failed for message ${messageId}`, messageId: messageId, status: "failed"};
                }
                log:printInfo(string `[Replay] Successfully replayed message ${messageId}`);
                return {message: string `Message ${messageId} replayed successfully`, messageId: messageId, status: "success"};
            }

            // Not the target — nack it so it stays in the store and try next
            error? nackResult = failureStore->acknowledge(failedMsg.id, success = false);
            if nackResult is error {
                log:printWarn(string `[Replay] Could not nack message ${failedMsg.id}: ${nackResult.message()}`);
            }
            skippedIds.push(failedMsg.id);
            attempt += 1;
        }

        return <http:NotFound>{body: {message: string `Message with ID '${messageId}' not found in the failure store`}};
    }

    // POST /replay/messages
    // Replays all currently pending failed messages in the failure store.
    resource function post messages() returns ReplayResponse|error {
        int replayedCount = 0;
        int failedCount = 0;

        while true {
            messaging:Message|error? retrieved = failureStore->retrieve();
            if retrieved is error {
                return retrieved;
            }
            if retrieved is () {
                break;
            }
            messaging:Message failedMsg = retrieved;

            // Acknowledge (remove) the message before replaying
            error? ackResult = failureStore->acknowledge(failedMsg.id, success = true);
            if ackResult is error {
                log:printWarn(string `[Replay] Could not acknowledge message ${failedMsg.id}: ${ackResult.message()}`);
            }

            pipeline:ExecutionSuccess|pipeline:ExecutionError replayResult = adtPipeline.execute(failedMsg.payload);
            if replayResult is pipeline:ExecutionError {
                log:printError(string `[Replay] Replay failed for message ${failedMsg.id}: ${replayResult.message()}`, replayResult);
                failedCount += 1;
            } else {
                log:printInfo(string `[Replay] Successfully replayed message ${failedMsg.id}`);
                replayedCount += 1;
            }
        }

        return {
            message: string `Replay complete. Succeeded: ${replayedCount}, Failed: ${failedCount}`,
            status: failedCount == 0 ? "success" : "partial"
        };
    }
}
