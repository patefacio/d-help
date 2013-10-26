import opmix.ut;
import b;

mixin UTInit!__MODULE__;

version(unittest) import std.stdio;

unittest {
  writeln("A: This is an unnamed import");
}

@UT("AFoo") unittest {
  writeln("A: Foo is clean");
}

@UT("ABar") unittest {
  writeln("A: Bar is not clean");
  throw new Exception("BBar no good");
}
