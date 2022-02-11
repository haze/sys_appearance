#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <Network/Network.h>
#import <dispatch/dispatch.h>

@interface AppearanceServer : NSObject

@property(nonatomic, strong) nw_listener_t listener;
@property(nonatomic, strong) dispatch_queue_t listenerDispatchQueue;
@property(nonatomic, strong) dispatch_queue_t connectionDispatchQueue;
@property(nonatomic, strong) dispatch_queue_t messageSendDispatchQueue;
@property(nonatomic, strong) NSMutableArray<nw_connection_t> *connections;

@end

@interface AppearanceObserver : NSObject
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property(nonatomic, strong) AppearanceObserver *appearanceObserver;
@property(nonatomic, strong) AppearanceServer *appearanceServer;

@end

void sendAppearanceToConnection(nw_connection_t connection, bool isDark,
                                dispatch_queue_t dispatchQueue);
