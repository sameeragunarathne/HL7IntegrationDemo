import ballerina/http;
import ballerina/jwt;
import ballerina/log;
import ballerina/messaging;

listener http:Listener managementListener = check new (managementApiPort);
const string X_JWT_HEADER = "x-jwt-assertion";
const string ENDUSER_CLAIM = "http://wso2.org/claims/enduser";
const string APPLICATION_ID_CLAIM = "http://wso2.org/claims/applicationid";

type ReplayAuditContext record {|
    string actor;
    string applicationId;
|};

function extractClaim(jwt:Payload payload, string claim) returns string? {
    if payload.hasKey(claim) {
        json claimValue = <json>payload.get(claim);
        if claimValue is string {
            return claimValue;
        }
    }
    return ();
}

function getReplayAuditContext(http:Request httpRequest) returns ReplayAuditContext {
    ReplayAuditContext auditContext = {actor: "unknown", applicationId: "unknown"};
    string|error jwtAssertion = httpRequest.getHeader(X_JWT_HEADER);
    if jwtAssertion is string {
        [jwt:Header, jwt:Payload]|error headerPayload = jwt:decode(jwtAssertion);
        if headerPayload is [jwt:Header, jwt:Payload] {
            [jwt:Header, jwt:Payload] [_, payload] = headerPayload;
            string? actor = extractClaim(payload, ENDUSER_CLAIM);
            if actor is string {
                auditContext.actor = actor;
            }
            string? applicationId = extractClaim(payload, APPLICATION_ID_CLAIM);
            if applicationId is string {
                auditContext.applicationId = applicationId;
            }
        }
    }
    return auditContext;
}

function logReplayAudit(http:Request httpRequest, string action, string messageId, string status, string detail = "") {
    ReplayAuditContext auditContext = getReplayAuditContext(httpRequest);
    string message = string `[AUDIT] User '${auditContext.actor}' from application '${auditContext.applicationId}' performed '${action}' for message '${messageId}' with status '${status}'.`;
    if detail.length() > 0 {
        message = string `${message} Details: ${detail}`;
    }
    log:printInfo(message,
        action = action,
        actor = auditContext.actor,
        applicationId = auditContext.applicationId,
        messageId = messageId,
        status = status,
        detail = detail
    );
}

service /replay on managementListener {

    // GET /replay/messages
    // Peeks at the next failed message from the failure store without removing it.
    resource function get messages(http:Request httpRequest) returns FailedMessageInfo|EmptyStoreResponse|error {
        messaging:Message|error? retrieved = failureStore->retrieve();
        if retrieved is error {
            return retrieved;
        }
        if retrieved is () {
            return {message: "No failed messages in the failure store"};
        }
        messaging:Message failedMsg = retrieved;
        logReplayAudit(httpRequest, "replay-message-peek", failedMsg.id, "available");
        // Acknowledge with failure=false to put it back (nack) so it stays in the store
        error? ackResult = failureStore->acknowledge(failedMsg.id, success = false);
        if ackResult is error {
            log:printWarn(string `[Replay] Could not nack message ${failedMsg.id} in failure store: ${ackResult.message()}`);
        }
        return {id: failedMsg.id, payload: failedMsg.payload};
    }

    // POST /replay/messages/[id]
    // Replays a specific failed message by its ID.
    // The failure store is polled until the message with the given ID is found (up to maxPeekAttempts).
    resource function post messages/[string messageId](http:Request httpRequest) returns ReplayResponse|http:NotFound|error {
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
                error? replayStoreResult = replayStore->store(failedMsg.payload);
                if replayStoreResult is error {
                    log:printError(string `[Replay] Failed to enqueue message ${messageId} to replay store: ${replayStoreResult.message()}`, replayStoreResult);
                    logReplayAudit(httpRequest, "replay-by-id", messageId, "failed", replayStoreResult.message());
                    return {message: string `Failed to enqueue message ${messageId} to replay store`, messageId: messageId, status: "failed"};
                }
                log:printInfo(string `[Replay] Enqueued message ${messageId} to replay store`);
                logReplayAudit(httpRequest, "replay-by-id", messageId, "queued");
                return {message: string `Message ${messageId} queued for replay successfully`, messageId: messageId, status: "success"};
            }

            // Not the target — nack it so it stays in the store and try next
            error? nackResult = failureStore->acknowledge(failedMsg.id, success = false);
            if nackResult is error {
                log:printWarn(string `[Replay] Could not nack message ${failedMsg.id}: ${nackResult.message()}`);
            }
            skippedIds.push(failedMsg.id);
            attempt += 1;
        }

        logReplayAudit(httpRequest, "replay-by-id", messageId, "not-found", "Message not found in failure store");
        return <http:NotFound>{body: {message: string `Message with ID '${messageId}' not found in the failure store`}};
    }

    // POST /replay/messages
    // Replays all currently pending failed messages in the failure store.
    resource function post messages(http:Request httpRequest) returns ReplayResponse|error {
        int queuedCount = 0;
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

            error? replayStoreResult = replayStore->store(failedMsg.payload);
            if replayStoreResult is error {
                log:printError(string `[Replay] Failed to enqueue message ${failedMsg.id} to replay store: ${replayStoreResult.message()}`, replayStoreResult);
                logReplayAudit(httpRequest, "replay-all", failedMsg.id, "failed", replayStoreResult.message());
                failedCount += 1;
            } else {
                log:printInfo(string `[Replay] Enqueued message ${failedMsg.id} to replay store`);
                logReplayAudit(httpRequest, "replay-all", failedMsg.id, "queued");
                queuedCount += 1;
            }
        }

        return {
            message: string `Replay queueing complete. Queued: ${queuedCount}, Failed: ${failedCount}`,
            status: failedCount == 0 ? "success" : "partial"
        };
    }
}
