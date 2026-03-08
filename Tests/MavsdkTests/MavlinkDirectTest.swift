import XCTest
import RxBlocking
import RxSwift
import GRPC
import NIO
@testable import Mavsdk

final class MavlinkDirectTest: XCTestCase {
    private var sut: MavlinkDirect!
    private var provider: TestMavlinkDirectProvider!
    private var server: Server!
    private var connection: ClientConnection!
    private var eventLoopGroup: MultiThreadedEventLoopGroup!

    override func setUpWithError() throws {
        try super.setUpWithError()

        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        provider = TestMavlinkDirectProvider()
        server = try Server.insecure(group: eventLoopGroup)
            .withServiceProviders([provider])
            .bind(host: "127.0.0.1", port: 0)
            .wait()

        let port = server.channel.localAddress!.port!
        connection = ClientConnection.insecure(group: eventLoopGroup)
            .connect(host: "127.0.0.1", port: port)

        let service = Mavsdk_Rpc_MavlinkDirect_MavlinkDirectServiceClient(channel: connection)
        sut = MavlinkDirect(service: service,
                            scheduler: ConcurrentDispatchQueueScheduler(qos: .default),
                            eventLoopGroup: eventLoopGroup)
    }

    override func tearDownWithError() throws {
        try connection?.close().wait()
        try server?.close().wait()
        try eventLoopGroup?.syncShutdownGracefully()

        sut = nil
        provider = nil
        connection = nil
        server = nil
        eventLoopGroup = nil

        try super.tearDownWithError()
    }

    func testTranslateFromRpcMessageMapsAllFields() {
        var rpcMessage = Mavsdk_Rpc_MavlinkDirect_MavlinkMessage()
        rpcMessage.messageName = "BATTERY_STATUS"
        rpcMessage.systemID = 1
        rpcMessage.componentID = 2
        rpcMessage.targetSystemID = 3
        rpcMessage.targetComponentID = 4
        rpcMessage.fieldsJson = "{\"id\":0}"

        let message = MavlinkDirect.MavlinkMessage.translateFromRpc(rpcMessage)

        XCTAssertEqual("BATTERY_STATUS", message.messageName)
        XCTAssertEqual(1, message.systemID)
        XCTAssertEqual(2, message.componentID)
        XCTAssertEqual(3, message.targetSystemID)
        XCTAssertEqual(4, message.targetComponentID)
        XCTAssertEqual("{\"id\":0}", message.fieldsJson)
    }

    func testTranslateFromRpcResultMapsAllEnums() {
        var rpcResult = Mavsdk_Rpc_MavlinkDirect_MavlinkDirectResult()
        rpcResult.result = .invalidMessage
        rpcResult.resultStr = "bad message"

        let result = MavlinkDirect.MavlinkDirectResult.translateFromRpc(rpcResult)

        XCTAssertEqual(.invalidMessage, result.result)
        XCTAssertEqual("bad message", result.resultStr)
    }

    func testSendMessageCompletesOnSuccess() {
        provider.sendResult = makeRPCResult(.success, "ok")
        let message = makeMessage()

        let event = sut.sendMessage(message: message).toBlocking().materialize()

        guard case .completed(let elements) = event else {
            return XCTFail("Expected completion")
        }

        XCTAssertTrue(elements.isEmpty)
        XCTAssertEqual(message.rpcMavlinkMessage, provider.lastSendRequest?.message)
    }

    func testSendMessageReturnsPluginErrorOnFailure() {
        provider.sendResult = makeRPCResult(.invalidField, "bad field")

        let event = sut.sendMessage(message: makeMessage()).toBlocking().materialize()

        guard case .failed(_, let error) = event else {
            return XCTFail("Expected an error event")
        }

        let pluginError = error as? MavlinkDirect.MavlinkDirectError
        XCTAssertEqual(MavlinkDirect.MavlinkDirectResult.Result.invalidField, pluginError?.code)
        XCTAssertEqual("bad field", pluginError?.description)
    }

    func testLoadCustomXmlCompletesOnSuccess() {
        provider.loadCustomXmlResult = makeRPCResult(.success, "ok")

        let event = sut.loadCustomXml(xmlContent: "<mavlink/>").toBlocking().materialize()

        guard case .completed(let elements) = event else {
            return XCTFail("Expected completion")
        }

        XCTAssertTrue(elements.isEmpty)
        XCTAssertEqual("<mavlink/>", provider.lastLoadCustomXmlRequest?.xmlContent)
    }

    func testLoadCustomXmlReturnsPluginErrorOnFailure() {
        provider.loadCustomXmlResult = makeRPCResult(.timeout, "timed out")

        let event = sut.loadCustomXml(xmlContent: "<mavlink/>").toBlocking().materialize()

        guard case .failed(_, let error) = event else {
            return XCTFail("Expected an error event")
        }

        let pluginError = error as? MavlinkDirect.MavlinkDirectError
        XCTAssertEqual(MavlinkDirect.MavlinkDirectResult.Result.timeout, pluginError?.code)
        XCTAssertEqual("timed out", pluginError?.description)
    }

    func testSubscribeMessageEmitsTranslatedMessages() throws {
        provider.streamedMessages = [makeRPCMessage(name: "BATTERY_STATUS", json: "{\"id\":1}")]

        let message = try sut.subscribeMessage(messageName: "BATTERY_STATUS")
            .take(1)
            .toBlocking(timeout: 2)
            .single()

        XCTAssertEqual("BATTERY_STATUS", provider.lastSubscribeMessageRequest?.messageName)
        XCTAssertEqual("BATTERY_STATUS", message.messageName)
        XCTAssertEqual("{\"id\":1}", message.fieldsJson)
    }

    private func makeMessage() -> MavlinkDirect.MavlinkMessage {
        MavlinkDirect.MavlinkMessage(messageName: "COMMAND_LONG",
                                     systemID: 1,
                                     componentID: 2,
                                     targetSystemID: 3,
                                     targetComponentID: 4,
                                     fieldsJson: "{\"command\":176}")
    }

    private func makeRPCResult(_ result: Mavsdk_Rpc_MavlinkDirect_MavlinkDirectResult.Result,
                               _ description: String) -> Mavsdk_Rpc_MavlinkDirect_MavlinkDirectResult {
        var rpcResult = Mavsdk_Rpc_MavlinkDirect_MavlinkDirectResult()
        rpcResult.result = result
        rpcResult.resultStr = description
        return rpcResult
    }

    private func makeRPCMessage(name: String, json: String) -> Mavsdk_Rpc_MavlinkDirect_MavlinkMessage {
        var rpcMessage = Mavsdk_Rpc_MavlinkDirect_MavlinkMessage()
        rpcMessage.messageName = name
        rpcMessage.systemID = 1
        rpcMessage.componentID = 2
        rpcMessage.targetSystemID = 3
        rpcMessage.targetComponentID = 4
        rpcMessage.fieldsJson = json
        return rpcMessage
    }
}

private final class TestMavlinkDirectProvider: Mavsdk_Rpc_MavlinkDirect_MavlinkDirectServiceProvider {
    var interceptors: Mavsdk_Rpc_MavlinkDirect_MavlinkDirectServiceServerInterceptorFactoryProtocol?

    var sendResult = Mavsdk_Rpc_MavlinkDirect_MavlinkDirectResult()
    var loadCustomXmlResult = Mavsdk_Rpc_MavlinkDirect_MavlinkDirectResult()
    var streamedMessages: [Mavsdk_Rpc_MavlinkDirect_MavlinkMessage] = []

    var lastSendRequest: Mavsdk_Rpc_MavlinkDirect_SendMessageRequest?
    var lastLoadCustomXmlRequest: Mavsdk_Rpc_MavlinkDirect_LoadCustomXmlRequest?
    var lastSubscribeMessageRequest: Mavsdk_Rpc_MavlinkDirect_SubscribeMessageRequest?

    func sendMessage(request: Mavsdk_Rpc_MavlinkDirect_SendMessageRequest,
                     context: StatusOnlyCallContext) -> EventLoopFuture<Mavsdk_Rpc_MavlinkDirect_SendMessageResponse> {
        lastSendRequest = request
        var response = Mavsdk_Rpc_MavlinkDirect_SendMessageResponse()
        response.mavlinkDirectResult = sendResult
        return context.eventLoop.makeSucceededFuture(response)
    }

    func subscribeMessage(request: Mavsdk_Rpc_MavlinkDirect_SubscribeMessageRequest,
                          context: StreamingResponseCallContext<Mavsdk_Rpc_MavlinkDirect_MessageResponse>) -> EventLoopFuture<GRPCStatus> {
        lastSubscribeMessageRequest = request

        let futures = streamedMessages.map { message in
            var response = Mavsdk_Rpc_MavlinkDirect_MessageResponse()
            response.message = message
            return context.sendResponse(response)
        }

        return EventLoopFuture.andAllSucceed(futures, on: context.eventLoop).map { .ok }
    }

    func loadCustomXml(request: Mavsdk_Rpc_MavlinkDirect_LoadCustomXmlRequest,
                       context: StatusOnlyCallContext) -> EventLoopFuture<Mavsdk_Rpc_MavlinkDirect_LoadCustomXmlResponse> {
        lastLoadCustomXmlRequest = request
        var response = Mavsdk_Rpc_MavlinkDirect_LoadCustomXmlResponse()
        response.mavlinkDirectResult = loadCustomXmlResult
        return context.eventLoop.makeSucceededFuture(response)
    }
}
