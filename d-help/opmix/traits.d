/**
   Template support functions
*/

module opmix.traits;

public import std.traits;

// custom <dmodule traits public_section>

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

// end <dmodule traits public_section>

/**
   License: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
*/
