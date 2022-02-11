#include "app.h"

#define BONJOUR_SERVICE_TCP_TYPE "_sys_appearance._tcp"
#define BONJOUR_SERVICE_DOMAIN "local"

@implementation AppearanceServer

- (id)init {
  self = [super init];
  self.connections = [NSMutableArray arrayWithCapacity:8];

  self.listenerDispatchQueue = dispatch_queue_create(
      "cool.haze.sys_appearance.listener", DISPATCH_QUEUE_SERIAL);
  self.connectionDispatchQueue = dispatch_queue_create(
      "cool.haze.sys_appearance.connection_array", DISPATCH_QUEUE_SERIAL);
  self.messageSendDispatchQueue = dispatch_queue_create(
      "cool.haze.sys_appearance.msg_send", DISPATCH_QUEUE_SERIAL);

  nw_parameters_t listenerParameters = nil;

  listenerParameters = nw_parameters_create_secure_tcp(
      NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);

  self.listener = nw_listener_create(listenerParameters);

  nw_release(listenerParameters);

  nw_endpoint_t localEndpoint = nw_endpoint_create_host("", "");

  nw_advertise_descriptor_t advertise =
      nw_advertise_descriptor_create_bonjour_service(
          nw_endpoint_get_hostname(localEndpoint), BONJOUR_SERVICE_TCP_TYPE,
          BONJOUR_SERVICE_DOMAIN);
  nw_listener_set_advertise_descriptor(self.listener, advertise);
  nw_release(advertise);

  nw_listener_set_advertised_endpoint_changed_handler(
      self.listener, ^(nw_endpoint_t _Nonnull advertised_endpoint, bool added) {
        NSLog(@"Listener %@ on %s", added ? @"added" : @"removed",
              nw_endpoint_get_bonjour_service_name(advertised_endpoint));
      });

  nw_listener_set_queue(self.listener, self.listenerDispatchQueue);

  nw_retain(self.listener);

  nw_listener_set_state_changed_handler(
      self.listener, ^(nw_listener_state_t state, nw_error_t error) {
        if (error != nil) {
          NSLog(@"Error encountered on listener state change: %@", error);
        } else {
          switch (state) {
          case nw_listener_state_ready: {
            uint16_t port = nw_listener_get_port(self.listener);
            NSLog(@"Accepting connections on :%d", port);
            printf("%u\n", (unsigned int)port);
            break;
          }
          case nw_listener_state_failed:
            NSLog(@"failed state");
            break;
          case nw_listener_state_cancelled:
            NSLog(@"cancelled state");
            nw_release(self.listener);
            break;
          default:
            break;
          }
        }
      });

  nw_listener_set_new_connection_handler(
      self.listener, ^(nw_connection_t newConnection) {
        NSLog(@"Got new connection %@", newConnection);
        nw_retain(newConnection);

        nw_connection_set_queue(newConnection, self.listenerDispatchQueue);
        nw_connection_set_state_changed_handler(
            newConnection, ^(nw_connection_state_t state, nw_error_t error) {
              if (state == nw_connection_state_cancelled) {
                nw_release(newConnection);
              } else if (state == nw_connection_state_ready) {
                NSAppearanceName appearanceName =
                    [NSApplication.sharedApplication.effectiveAppearance name];
                bool isDark = [appearanceName containsString:@"Dark"];
                sendAppearanceToConnection(newConnection, isDark,
                                           self.messageSendDispatchQueue);
              } else if (state == nw_connection_state_failed) {
                dispatch_async(self.connectionDispatchQueue, ^{
                  [self.connections removeObject:newConnection];
                  NSLog(@"Removed connection %@ after failiure", newConnection);
                });
              }
            });
        nw_connection_start(newConnection);

        dispatch_async(self.connectionDispatchQueue, ^{
          [self.connections addObject:newConnection];
        });
      });

  nw_listener_start(self.listener);
  return self;
}

- (void)notifyOfNewAppearance:(NSAppearanceName)appearanceName {
  bool isDark = [appearanceName containsString:@"Dark"];
  NSLog(@"Notifying of %@", appearanceName);
  dispatch_async(self.messageSendDispatchQueue, ^{
    for (nw_connection_t connection in self.connections) {
      sendAppearanceToConnection(connection, isDark,
                                 self.messageSendDispatchQueue);
    }
  });
}

@end

@implementation AppearanceObserver

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
  NSAppearanceName appearanceName =
      [NSApplication.sharedApplication.effectiveAppearance name];
  AppDelegate *appDelegate = NSApplication.sharedApplication.delegate;
  [appDelegate.appearanceServer notifyOfNewAppearance:appearanceName];
}

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  self.appearanceObserver = [AppearanceObserver new];
  self.appearanceServer = [AppearanceServer new];

  [NSApplication.sharedApplication
      addObserver:self.appearanceObserver
       forKeyPath:@"effectiveAppearance"
          options:NSKeyValueObservingOptionInitial |
                  NSKeyValueObservingOptionNew

          context:nil];
}

@end

void sendAppearanceToConnection(nw_connection_t connection, bool isDark,
                                dispatch_queue_t dispatchQueue) {
  dispatch_data_t dispatchData;
  if (isDark) {
    dispatchData = dispatch_data_create("dark\n", 5, dispatchQueue,
                                        ^{
                                        });
  } else {
    dispatchData = dispatch_data_create("light\n", 6, dispatchQueue,
                                        ^{
                                        });
  }
  nw_connection_send(connection, dispatchData,
                     NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true,
                     ^(nw_error_t _Nullable error) {
                       if (error != NULL) {
                         NSLog(@"send error: %@", error);
                       }
                     });
}

int main(int argc, const char *argv[]) {
  NSApplication.sharedApplication.delegate = [AppDelegate new];
  NSApplicationMain(argc, argv);
}
