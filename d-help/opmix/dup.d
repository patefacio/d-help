/**
   Support for generalized dup
*/

module opmix.dup;

import std.algorithm;
import std.string;
import std.traits;

/**
   Set this to true to see what is going on at compile time
*/
const(bool) LogDupCompile = false;


// custom <dmodule dup public_section>

template DeepUnqual(T) {
  static if(isAssociativeArray!T) {
    alias Unqual!(Unqual!(ValueType!T)[Unqual!(KeyType!T)]) DeepUnqual;    
  } else static if(isDynamicArray!T) {
    alias Unqual!(Unqual!(ArrayElementType!T)[]) DeepUnqual;
  } else static if(isPointer!T) {
    alias Unqual!(PointerTarget!T) * DeepUnqual;
  } else {
    alias Unqual!T DeepUnqual;
  }
}

template ArrayElementType(T : U[], U) {
  alias U ArrayElementType;
}

template isArrayOfNonMutable(T) {
  static if(isDynamicArray!T && 
            (is(ArrayElementType!T == const) ||
             is(ArrayElementType!T == immutable))) {
    enum isArrayOfImmutable = true;
  } else {
    enum isArrayOfImmutable = false;
  }
}

template isArrayOfImmutable(T) {
  static if(isDynamicArray!T && is(ArrayElementType!T == immutable)) {
    enum isArrayOfImmutable = true;
  } else {
    enum isArrayOfImmutable = false;
  }
}

@property auto gdup(T)(const ref T t) {
  DeepUnqual!T result;
  static if(LogDupCompile) 
    pragma(msg, 
           "CT: gdup prop on (", 
           typeof(result), " <= ", typeof(t), ")");
  gdup(result, t);
  return result;
}

ref T opDupPreferred(T, F)(ref T target, const ref F src)
  if(is(DeepUnqual!T == DeepUnqual!F)) {
  static if(LogDupCompile) 
    pragma(msg, 
           "CT: opDupPreferred on (", typeof(target), " <= ", typeof(src), ")");
  static if(is(T==struct) && __traits(compiles, (src.dup))) {
    static if(LogDupCompile) 
      pragma(msg, 
             "CT: ...Using ", 
             typeof(src).stringof, ".dup for dup of ", typeof(src));
    target = src.dup;
  } else {
    static if(LogDupCompile) 
      pragma(msg, "CT: ...Using gdup for dup of ", typeof(src));
    gdup(target, src);
  }
  return target;
}

void gdup(T1, T2)(ref T1 t1, const ref T2 t2) {
  static assert(is(Unqual!(typeof(t1)) == typeof(t1)), 
                "Must dup into mutable "~typeof(t1).stringof~
                " <= "~typeof(t2).stringof);

  static if(LogDupCompile) 
    pragma(msg, 
           "CT: gdup(t1,t2) prop on (", 
           typeof(t1), " <= ", typeof(t2), ")");

  if(&t1 is &t2) {
    // Postblit may be using gdup - get fresh temp
    typeof(t1) temp;
    gdup(temp, t2);
    swap(t1, temp);
  } else {
    static if(isBasicType!T1 || is(T1==enum)) {
      static if(LogDupCompile) 
        pragma(msg, "CT: ...T1 is basic type ", T1);
      t1 = t2;
    } else static if(isArrayOfImmutable!T1 && isArrayOfImmutable!T2) {
      static if(LogDupCompile) 
        pragma(msg, "CT: ...T1 is array of immutable ", T1, " as is t2 ", T2);
      t1 = t2.idup;
    } else static if(isDynamicArray!T1) {
      static if(hasAliasing!(ArrayElementType!T1)) {
        static if(LogDupCompile) 
          pragma(msg, "CT: ...T1 is array mutable ", T1);
        foreach(ref val2; t2) {
          Unqual!(ArrayElementType!T1) val1;
          opDupPreferred(val1, val2);
          t1 ~= val1;
        }
      } else {
        static if(LogDupCompile) 
          pragma(msg, "CT: ...T1 is array of type with no aliasing ", T1);
        t1 = t2.dup;
      }
    } else static if(isAssociativeArray!T1) {
      static if(LogDupCompile) 
        pragma(msg, "CT: ...T1 is assoc array ", T1, 
               " w value type ", ValueType!T1, " aka ", typeof(t1));
  
      alias KeyType!(T1) AAKeyType;
      alias ValueType!(T1) AAValueType;
      alias DeepUnqual!(AAValueType)[DeepUnqual!(AAKeyType)] NoConstAssocArr;
      // NOTE: k here *is* copied with postblit, which is a shame. It would be
      // better if the foreach would be like
      // foreach(ref const(K) k, ref V v2; ...)
      // foreach(ref const(K) k, ref const(V) v2; ...)
      // per the user's choosing
      foreach(k, ref v2; cast(DeepUnqual!(typeof(t2)))t2) {
        AAValueType v1;
        opDupPreferred(v1, v2);
        t1[k] = v1;
      }
      static if(LogDupCompile) pragma(msg, "CT: ...T1 done assoc array ", T1);
    } else static if(is(T1==struct)) {
      static if(LogDupCompile) pragma(msg, "CT: ...T1 is struct ", T1);
        foreach (i, ignore ; typeof(T1.tupleof)) {
          static if(T1.tupleof[i].stringof.endsWith(".this")) {
            static assert(0, "no dup of nested non static structs!");
          }
          static if(LogDupCompile) 
            pragma(msg, "CT: .....dupping field ", t2.tupleof[i].stringof);
          opDupPreferred(t1.tupleof[i], t2.tupleof[i]);
        }
    } else static if(isPointer!T1) {
      static if(LogDupCompile) pragma(msg, "CT: ...T1 is pointer ", T1);
      alias Unqual!(PointerTarget!T1) Target;
      if(t2) {
        static if(__traits(compiles, (t1 = new Target))) {
          t1 = new Target;
          opDupPreferred(*t1, *t2); 
        } else {
          static assert(0, "gdup will not work with "~
                        Target.stringof~
                        " since can not be default heap allocated");
        }
      }
    } else static if(is(T1==union)) {
        t1 = t2;
    } else static if(is(T1==class)) {
      static if(LogDupCompile) 
        pragma(msg, "CT: ...T1 is a class else entirely ", T1);
      static assert(0, "Class gdup not supported, requested type "~T1.stringof);
    } else {
      static assert(0, "Missing gdup support for "~T1.stringof);
    }
  }
}

// end <dmodule dup public_section>

/**
   License: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
*/
