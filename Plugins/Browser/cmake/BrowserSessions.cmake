# Apply a small compatibility overlay to the pinned CDP-for-CPP dependency.
# Approval-based Chrome/Edge connections expose only the browser WebSocket:
# /json discovery and individual page WebSockets are deliberately unavailable.
# Keep upstream sources intact, and fail configuration if a patch no longer fits.
get_target_property(rmt_cdp_source cdp SOURCE_DIR)
set(rmt_cdp_overlay "${CMAKE_CURRENT_BINARY_DIR}/cdp-sessions")
file(COPY "${rmt_cdp_source}/include/" DESTINATION "${rmt_cdp_overlay}/include")
set(rmt_cdp_files
    include/cdp/protocol/CDPConnection.hpp
    include/cdp/protocol/CDPClient.hpp
    src/protocol/CDPConnection.cpp
    src/protocol/CDPClient.cpp
    src/browser/QuickStart.cpp)
foreach(path IN LISTS rmt_cdp_files)
    configure_file("${rmt_cdp_source}/${path}" "${rmt_cdp_overlay}/${path}" COPYONLY)
endforeach()

function(rmt_cdp_replace path before after)
    set(file "${rmt_cdp_overlay}/${path}")
    file(READ "${file}" content)
    string(REPLACE "\r\n" "\n" content "${content}")
    string(FIND "${content}" "${before}" position)
    if(position EQUAL -1)
        message(FATAL_ERROR "CDP session compatibility patch no longer matches ${path}")
    endif()
    string(REPLACE "${before}" "${after}" content "${content}")
    file(WRITE "${file}" "${content}")
endfunction()

rmt_cdp_replace(include/cdp/protocol/CDPConnection.hpp
    "bool isConnected() const { return ws_.isConnected(); }"
    "bool isConnected() const { return parent_ ? sessionAttached_.load() && parent_->isConnected() : ws_.isConnected(); }\n    bool connectSession(CDPConnection& parent, const std::string& targetId);")
rmt_cdp_replace(include/cdp/protocol/CDPConnection.hpp
    "int64_t nextMessageId() { return ++messageId_; }"
    "int64_t nextMessageId() { return parent_ ? parent_->nextMessageId() : ++messageId_; }\n    bool sendRequest(const CDPRequest& request);\n    CDPConnection* parent_ = nullptr;\n    std::string sessionId_;\n    std::atomic<bool> sessionAttached_{false};\n    std::mutex sessionsMutex_;\n    std::map<std::string, CDPConnection*> sessions_;")
rmt_cdp_replace(include/cdp/protocol/CDPConnection.hpp
    "return messageThreadRunning_.load() && std::this_thread::get_id() == messageThreadId_;"
    "return parent_ ? parent_->isMessageThread() : messageThreadRunning_.load() && std::this_thread::get_id() == messageThreadId_;")
rmt_cdp_replace(src/protocol/CDPConnection.cpp
    "void CDPConnection::disconnect() {"
    [=[bool CDPConnection::connectSession(CDPConnection& parent, const std::string& targetId) {
    auto response = parent.sendCommandSync("Target.attachToTarget",
        JsonObject{{"targetId", targetId}, {"flatten", true}});
    if (response.hasError) return false;
    const auto id = response.result["sessionId"].getString();
    if (id.empty()) return false;
    parent_ = &parent;
    sessionId_ = id;
    sessionAttached_ = true;
    std::lock_guard<std::mutex> lock(parent.sessionsMutex_);
    parent.sessions_[id] = this;
    return true;
}

bool CDPConnection::sendRequest(const CDPRequest& request) {
    if (!parent_) return ws_.send(request.serialize());
    JsonObject message{{"id", static_cast<double>(request.id)}, {"method", request.method},
        {"params", request.params}, {"sessionId", sessionId_}};
    return parent_->ws_.send(JsonValue(message).serialize());
}

void CDPConnection::disconnect() {
    if (parent_) {
        auto* parent = parent_;
        {
            std::lock_guard<std::mutex> lock(parent->sessionsMutex_);
            parent->sessions_.erase(sessionId_);
        }
        if (parent->isConnected())
            parent->sendCommand("Target.detachFromTarget", JsonObject{{"sessionId", sessionId_}});
        parent_ = nullptr;
        sessionAttached_ = false;
        sessionId_.clear();
    }]=])
rmt_cdp_replace(src/protocol/CDPConnection.cpp
    "void CDPConnection::startMessageThread() {"
    "void CDPConnection::startMessageThread() {\n    if (parent_) return; // The browser connection dispatches all page messages.")
rmt_cdp_replace(src/protocol/CDPConnection.cpp
    "if (!ws_.send(message)) {" "if (!sendRequest(request)) {")
rmt_cdp_replace(src/protocol/CDPConnection.cpp
    "if (messageThreadRunning_.load()) {" "if (parent_ || messageThreadRunning_.load()) {")
rmt_cdp_replace(src/protocol/CDPConnection.cpp
    "JsonValue json = JsonValue::parse(message);"
    [=[JsonValue json = JsonValue::parse(message);
        // The parent owns the socket and its child pointers are protected during dispatch.
        if (!parent_ && json.contains("sessionId")) {
            std::lock_guard<std::mutex> lock(sessionsMutex_);
            auto child = sessions_.find(json["sessionId"].getString());
            if (child != sessions_.end()) child->second->handleMessage(message);
            return;
        }
        if (!parent_ && json["method"].getString() == "Target.detachedFromTarget") {
            std::lock_guard<std::mutex> lock(sessionsMutex_);
            auto child = sessions_.find(json["params"]["sessionId"].getString());
            if (child != sessions_.end()) child->second->sessionAttached_ = false;
        }]=])
rmt_cdp_replace(include/cdp/protocol/CDPClient.hpp
    "bool connectToBrowser();"
    "bool connectToBrowser();\n    bool connectSession(CDPClient& browser, const std::string& targetId);")
rmt_cdp_replace(src/protocol/CDPClient.cpp
    "void CDPClient::disconnect() {"
    [=[bool CDPClient::connectSession(CDPClient& browser, const std::string& targetId) {
    if (!connection_.connectSession(browser.connection(), targetId)) {
        lastError_ = "Could not attach browser page session";
        return false;
    }
    enableDomains();
    return true;
}

void CDPClient::disconnect() {]=])
rmt_cdp_replace(src/protocol/CDPClient.cpp
    "return CDPConnection::discoverTargets(config_.host, config_.port);"
    [=[if (!isConnected()) return CDPConnection::discoverTargets(config_.host, config_.port);
    const auto response = Target.getTargets();
    std::vector<CDPTarget> targets;
    if (response.hasError) return targets;
    for (const auto& info : response.result["targetInfos"].asArray()) {
        auto target = CDPTarget::fromJson(info);
        target.id = info["targetId"].getString();
        // High-level page creation checks for a nonempty endpoint before attaching.
        target.webSocketDebuggerUrl = "session://" + target.id;
        targets.push_back(std::move(target));
    }
    return targets;]=])
rmt_cdp_replace(src/browser/QuickStart.cpp
    "pageClient->connect(target.webSocketDebuggerUrl)"
    "pageClient->connectSession(browserClient_, target.id)")
rmt_cdp_replace(src/browser/QuickStart.cpp
    "pageClient->connect(wsUrl)"
    "pageClient->connectSession(browserClient_, targetId)")

get_target_property(rmt_cdp_sources cdp SOURCES)
foreach(path src/protocol/CDPConnection.cpp src/protocol/CDPClient.cpp src/browser/QuickStart.cpp)
    list(REMOVE_ITEM rmt_cdp_sources "${path}" "${rmt_cdp_source}/${path}")
    list(APPEND rmt_cdp_sources "${rmt_cdp_overlay}/${path}")
endforeach()
set_property(TARGET cdp PROPERTY SOURCES "${rmt_cdp_sources}")
target_include_directories(cdp BEFORE PUBLIC "$<BUILD_INTERFACE:${rmt_cdp_overlay}/include>")
