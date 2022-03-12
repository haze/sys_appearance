#include "app.h"
#include <stdlib.h>

#define BONJOUR_SERVICE_TCP_TYPE "_sys_appearance._tcp"
#define BONJOUR_SERVICE_DOMAIN "local"

#define NSEC_PER_MS 1000000

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

  nw_endpoint_t localEndpoint = nw_endpoint_create_host("::", "0");

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

nw_connection_t connect_to_local_instance() {
  // TODO(haze): see if it works without
  nw_endpoint_t localEndpoint = nw_endpoint_create_host("::", "0");
  nw_endpoint_t endpoint = nw_endpoint_create_bonjour_service(
      nw_endpoint_get_hostname(localEndpoint), BONJOUR_SERVICE_TCP_TYPE,
      BONJOUR_SERVICE_DOMAIN);

  nw_parameters_t parameters = nw_parameters_create_secure_tcp(
      NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);

  nw_connection_t connection = nw_connection_create(endpoint, parameters);
  nw_release(endpoint);
  nw_release(parameters);

  return connection;
}

void receiveLoop(nw_connection_t connection) {
  nw_connection_receive(
      connection, 1, UINT32_MAX,
      ^(dispatch_data_t content, nw_content_context_t context, bool is_complete,
        nw_error_t receive_error) {
        nw_retain(context);
        dispatch_block_t schedule_next_receive = ^{
          if (is_complete &&
              (context == NULL || nw_content_context_get_is_final(context))) {
            return;
          }

          // If there was no error in receiving, request more data
          if (receive_error == NULL) {
            receiveLoop(connection);
          }
          nw_release(context);
        };

        if (content != NULL) {
          // If there is content, write it to stdout asynchronously
          schedule_next_receive = Block_copy(schedule_next_receive);
          dispatch_write(
              1, content, dispatch_get_main_queue(),
              ^(__unused dispatch_data_t _Nullable data, int stdout_error) {
                if (stdout_error != 0) {
                  errno = stdout_error;
                  NSLog(@"Failed to write current system appearance to stdout: "
                        @"%d",
                        errno);
                }
                Block_release(schedule_next_receive);
                exit(0);
              });
        } else {
          // Content was NULL, so directly schedule the next receive
          schedule_next_receive();
        }
      });
}

void printOneshotResult(uint16_t timeoutInMilliseconds) {
  nw_connection_t connection = connect_to_local_instance();

  if (connection == NULL) {
    NSLog(@"Failed to find local instance running using bonjour");
    return;
  }

  nw_connection_set_queue(connection, dispatch_get_main_queue());
  nw_retain(connection);

  nw_connection_set_state_changed_handler(
      connection, ^(nw_connection_state_t state, nw_error_t error) {
        nw_endpoint_t remote = nw_connection_copy_endpoint(connection);
        if (state == nw_connection_state_waiting) {
          NSLog(@"Connect to %s port %u failed, is waiting",
                nw_endpoint_get_hostname(remote), nw_endpoint_get_port(remote));
        } else if (state == nw_connection_state_failed) {
          NSLog(@"Connect to %s port %u failed",
                nw_endpoint_get_hostname(remote), nw_endpoint_get_port(remote));
        } else if (state == nw_connection_state_cancelled) {
          // Release the primary reference on the connection
          // that was taken at creation time
          nw_release(connection);
        }

        nw_release(remote);
      });

  nw_connection_start(connection);

  dispatch_queue_t globalQueue =
      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
  dispatch_source_t timerDispatchSource =
      dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, globalQueue);

  if (timerDispatchSource) {
    dispatch_time_t startTime =
        dispatch_time(DISPATCH_TIME_NOW, timeoutInMilliseconds * NSEC_PER_MS);
    dispatch_source_set_timer(timerDispatchSource, startTime,
                              DISPATCH_TIME_FOREVER, 8000ull);
    dispatch_source_set_event_handler(timerDispatchSource, ^() {
      dispatch_source_cancel(timerDispatchSource);
      NSLog(@"Timeout reached. Forcibly exiting...");
      exit(0);
    });
    dispatch_resume(timerDispatchSource);
  } else {
    NSLog(@"Failed to create timeout timer");
  }

  receiveLoop(connection);

  dispatch_main();
}

int main(int argc, const char *argv[]) {
  uint16_t oneshotTimeoutInMilliseconds = 5000;
  for (size_t arg = 0; arg < argc; arg += 1) {
    if (strcmp(argv[arg], "oneshot") == 0) {
      if (argc > arg + 1) {
        NSLog(@"Interpreting next argument as TCP connection timeout...");
        oneshotTimeoutInMilliseconds = strtoul(argv[arg + 1], NULL, 10);
        NSLog(@"Custom timeout: %dms", oneshotTimeoutInMilliseconds);
      }
      printOneshotResult(oneshotTimeoutInMilliseconds);
      return EXIT_SUCCESS;
    }
  }
  NSApplication.sharedApplication.delegate = [AppDelegate new];
  NSApplicationMain(argc, argv);
}
