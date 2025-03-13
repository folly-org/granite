# granite
An engine made to be used for [folly](https://github.com/folly-org/folly)

# how to use
```sh
zig fetch --save git+https://github.com/folly-org/granite#main
```

now add the dependency to your `build.zig`:
```zig
const granite = b.dependency("granite", .{
    .target = target,
    .optimize = optimize,
});

exe_mod.addImport("granite", granite.module("granite"));
```