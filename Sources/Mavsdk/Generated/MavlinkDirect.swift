import Foundation
import RxSwift
import GRPC
import NIO

/**
 Enable direct MAVLink communication using libmav.
 */
public class MavlinkDirect {
    private let service: Mavsdk_Rpc_MavlinkDirect_MavlinkDirectServiceClient
    private let scheduler: SchedulerType
    private let clientEventLoopGroup: EventLoopGroup

    /**
     Initializes a new `MavlinkDirect` plugin.

     Normally never created manually, but used from the `Drone` helper class instead.

     - Parameters:
        - address: The address of the `MavsdkServer` instance to connect to
        - port: The port of the `MavsdkServer` instance to connect to
        - scheduler: The scheduler to be used by `Observable`s
     */
    public convenience init(address: String = "localhost",
                            port: Int32 = 50051,
                            scheduler: SchedulerType = ConcurrentDispatchQueueScheduler(qos: .background)) {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        let channel = ClientConnection.insecure(group: eventLoopGroup).connect(host: address, port: Int(port))
        let service = Mavsdk_Rpc_MavlinkDirect_MavlinkDirectServiceClient(channel: channel)

        self.init(service: service, scheduler: scheduler, eventLoopGroup: eventLoopGroup)
    }

    init(service: Mavsdk_Rpc_MavlinkDirect_MavlinkDirectServiceClient,
         scheduler: SchedulerType,
         eventLoopGroup: EventLoopGroup) {
        self.service = service
        self.scheduler = scheduler
        self.clientEventLoopGroup = eventLoopGroup
    }

    public struct RuntimeMavlinkDirectError: Error {
        public let description: String

        init(_ description: String) {
            self.description = description
        }
    }

    public struct MavlinkDirectError: Error {
        public let code: MavlinkDirect.MavlinkDirectResult.Result
        public let description: String
    }

    /**
     A complete MAVLink message with all header information and fields.
     */
    public struct MavlinkMessage: Equatable {
        public let messageName: String
        public let systemID: UInt32
        public let componentID: UInt32
        public let targetSystemID: UInt32
        public let targetComponentID: UInt32
        public let fieldsJson: String

        /**
         Initializes a new `MavlinkMessage`.

         - Parameters:
            - messageName: MAVLink message name (e.g., "HEARTBEAT", "GLOBAL_POSITION_INT")
            - systemID: System ID of the sender (for received messages)
            - componentID: Component ID of the sender (for received messages)
            - targetSystemID: Target system ID (for sending, 0 for broadcast)
            - targetComponentID: Target component ID (for sending, 0 for broadcast)
            - fieldsJson: All message fields as single JSON object
         */
        public init(messageName: String,
                    systemID: UInt32,
                    componentID: UInt32,
                    targetSystemID: UInt32,
                    targetComponentID: UInt32,
                    fieldsJson: String) {
            self.messageName = messageName
            self.systemID = systemID
            self.componentID = componentID
            self.targetSystemID = targetSystemID
            self.targetComponentID = targetComponentID
            self.fieldsJson = fieldsJson
        }

        internal var rpcMavlinkMessage: Mavsdk_Rpc_MavlinkDirect_MavlinkMessage {
            var rpcMavlinkMessage = Mavsdk_Rpc_MavlinkDirect_MavlinkMessage()
            rpcMavlinkMessage.messageName = messageName
            rpcMavlinkMessage.systemID = systemID
            rpcMavlinkMessage.componentID = componentID
            rpcMavlinkMessage.targetSystemID = targetSystemID
            rpcMavlinkMessage.targetComponentID = targetComponentID
            rpcMavlinkMessage.fieldsJson = fieldsJson
            return rpcMavlinkMessage
        }

        internal static func translateFromRpc(_ rpcMavlinkMessage: Mavsdk_Rpc_MavlinkDirect_MavlinkMessage) -> MavlinkMessage {
            MavlinkMessage(messageName: rpcMavlinkMessage.messageName,
                           systemID: rpcMavlinkMessage.systemID,
                           componentID: rpcMavlinkMessage.componentID,
                           targetSystemID: rpcMavlinkMessage.targetSystemID,
                           targetComponentID: rpcMavlinkMessage.targetComponentID,
                           fieldsJson: rpcMavlinkMessage.fieldsJson)
        }
    }

    /**
     Result type.
     */
    public struct MavlinkDirectResult: Equatable {
        public let result: Result
        public let resultStr: String

        /**
         Possible results returned for action requests.
         */
        public enum Result: Equatable {
            case unknown
            case success
            case error
            case invalidMessage
            case invalidField
            case connectionError
            case noSystem
            case timeout
            case UNRECOGNIZED(Int)

            internal var rpcResult: Mavsdk_Rpc_MavlinkDirect_MavlinkDirectResult.Result {
                switch self {
                case .unknown:
                    return .unknown
                case .success:
                    return .success
                case .error:
                    return .error
                case .invalidMessage:
                    return .invalidMessage
                case .invalidField:
                    return .invalidField
                case .connectionError:
                    return .connectionError
                case .noSystem:
                    return .noSystem
                case .timeout:
                    return .timeout
                case .UNRECOGNIZED(let i):
                    return .UNRECOGNIZED(i)
                }
            }

            internal static func translateFromRpc(_ rpcResult: Mavsdk_Rpc_MavlinkDirect_MavlinkDirectResult.Result) -> Result {
                switch rpcResult {
                case .unknown:
                    return .unknown
                case .success:
                    return .success
                case .error:
                    return .error
                case .invalidMessage:
                    return .invalidMessage
                case .invalidField:
                    return .invalidField
                case .connectionError:
                    return .connectionError
                case .noSystem:
                    return .noSystem
                case .timeout:
                    return .timeout
                case .UNRECOGNIZED(let i):
                    return .UNRECOGNIZED(i)
                }
            }
        }

        /**
         Initializes a new `MavlinkDirectResult`.

         - Parameters:
            - result: Result enum value
            - resultStr: Human-readable English string describing the result
         */
        public init(result: Result, resultStr: String) {
            self.result = result
            self.resultStr = resultStr
        }

        internal var rpcMavlinkDirectResult: Mavsdk_Rpc_MavlinkDirect_MavlinkDirectResult {
            var rpcMavlinkDirectResult = Mavsdk_Rpc_MavlinkDirect_MavlinkDirectResult()
            rpcMavlinkDirectResult.result = result.rpcResult
            rpcMavlinkDirectResult.resultStr = resultStr
            return rpcMavlinkDirectResult
        }

        internal static func translateFromRpc(_ rpcMavlinkDirectResult: Mavsdk_Rpc_MavlinkDirect_MavlinkDirectResult) -> MavlinkDirectResult {
            MavlinkDirectResult(result: Result.translateFromRpc(rpcMavlinkDirectResult.result),
                                resultStr: rpcMavlinkDirectResult.resultStr)
        }
    }

    /**
     Send a MAVLink message directly to the system.

     This allows sending any MAVLink message with full control over the message content.

     - Parameter message: The MAVLink message to send
     */
    public func sendMessage(message: MavlinkMessage) -> Completable {
        Completable.create { completable in
            var request = Mavsdk_Rpc_MavlinkDirect_SendMessageRequest()
            request.message = message.rpcMavlinkMessage

            do {
                let response = self.service.sendMessage(request)
                let result = try response.response.wait().mavlinkDirectResult
                if result.result == .success {
                    completable(.completed)
                } else {
                    completable(.error(MavlinkDirectError(code: MavlinkDirectResult.Result.translateFromRpc(result.result),
                                                          description: result.resultStr)))
                }
            } catch {
                completable(.error(error))
            }

            return Disposables.create()
        }
    }

    /**
     Subscribe to incoming MAVLink messages.

     This provides direct access to incoming MAVLink messages. Use an empty string
     in message_name to subscribe to all messages, or specify a message name
     (e.g., "HEARTBEAT") to filter for specific message types.

     - Parameter messageName: MAVLink message name to filter for, or an empty string to subscribe to all messages
     */
    public func subscribeMessage(messageName: String) -> Observable<MavlinkMessage> {
        Observable.create { [unowned self] observer in
            var request = Mavsdk_Rpc_MavlinkDirect_SubscribeMessageRequest()
            request.messageName = messageName

            let serverStreamingCall = self.service.subscribeMessage(request, handler: { response in
                observer.onNext(MavlinkMessage.translateFromRpc(response.message))
            })

            return Disposables.create {
                serverStreamingCall.cancel(promise: nil)
            }
        }
        .retry { error in
            error.map {
                guard $0 is RuntimeMavlinkDirectError else { throw $0 }
            }
        }
        .share(replay: 1)
    }

    /**
     Load custom MAVLink message definitions from XML.

     This allows loading custom MAVLink message definitions at runtime,
     extending the available message types beyond the built-in definitions.

     - Parameter xmlContent: The custom MAVLink XML definition content
     */
    public func loadCustomXml(xmlContent: String) -> Completable {
        Completable.create { completable in
            var request = Mavsdk_Rpc_MavlinkDirect_LoadCustomXmlRequest()
            request.xmlContent = xmlContent

            do {
                let response = self.service.loadCustomXml(request)
                let result = try response.response.wait().mavlinkDirectResult
                if result.result == .success {
                    completable(.completed)
                } else {
                    completable(.error(MavlinkDirectError(code: MavlinkDirectResult.Result.translateFromRpc(result.result),
                                                          description: result.resultStr)))
                }
            } catch {
                completable(.error(error))
            }

            return Disposables.create()
        }
    }
}
