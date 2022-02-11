# `sys_appearance`
##### get real time notifications of mac OS system appearance changes through a TCP socket

`sys_appearance` is a small mac OS utility that makes it easy for third party applications to get real time notifications of mac OS system appearance, as well as the current appearance.

This tool is meant to replace the rust implementation in [dark-notify](https://github.com/cormacrelf/dark-notify), because it uses nightly APIs which were unstable and no longer exist in recent versions of rust.

## Installation

```sh
make
```

## Usage

`sys_appearance` can handle multiple clients at once, so it is advised to keep one instance running
in the background (preferably using `launchd` and at launch.) For application instances that wish
to start a instance at will per session, the port will be echoed to standard out. This port is selected by
the kernel. 

You can test the tool by running `nc localhost <port>`. Along with seeing the current system
appearance, updates will also be sent through the socket.

`sys_appearance` will also advertise itself through Bonjour under `_sys_appearance._tcp`.

## License

BSD 2-Clause License
