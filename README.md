# MatrixFS

A stupid little FUSE filesystem that stores data as Matrix state objects, giving you a relatively low-cost distributed filesystem - albeit slow as molasses.

## Usage

```
$ bin/mount.matrixfs -h
Usage:
     mount.matrixfs  mountpoint [-h] [-d] [-o [opt,optkey=value,...]]
Fuse options: (2.9)
    -h                     help - print this help output
    -d |-o debug           enable internal FUSE debug output

fuse: failed to access mountpoint -h: No such file or directory
Filesystem options:
-o v                             Enables logging of MatrixFS actions
-o vv                            Enables verbose logging of MatrixFS actions
-o debug                         Enables logging of MatrixSDK communication
-o no_listen                     Don't listen to changes
-o hs=https://matrix.example.com The homeserver URL to communicate with
-o hs_domain=example.com         The homeserver domain to communicate with
-o access_token=TOKEN            An access token to use, to skip needing to log in
-o tokenfile=/PATH/TO/TOKEN      An access token to use, to skip needing to log in
-o user=USERNAME                 The username to log in with
-o pass=PASSWORD                 The password to log in with
-o passfile=/PATH/TO/PASS        The file to read the password from
```

## TODO?

- Stop storing the entire content of all objects in memory
- Handle multiple rooms
- Access arbitrary state?

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ananace/ruby-matrix-fs


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
