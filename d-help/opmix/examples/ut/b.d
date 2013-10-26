import opmix.ut;

mixin UTInit!__MODULE__;

version(unittest) import std.stdio;

unittest {
  writeln("B: This is an unnamed import");
}

@UT("BFoo") unittest {
  writeln("B: Foo is clean");
}

@UT("BBar") unittest {
  writeln("B: Bar is not clean");
  throw new Exception("BBar no good");
}
