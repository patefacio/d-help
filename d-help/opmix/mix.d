/**
   Provide some standard mixins. For background on the point of this see an
   interesting thread:
   http://forum.dlang.org/post/iphhuttpkogmfwpuvfla@forum.dlang.org
   
   Overcomes this problem:
   
   	writeln(  [1: 2]  ==   [1: 2] );  // true
   	writeln(S([1: 2]) == S([1: 2]));  // false
   
   by allowing:
   
   	writeln(typesDeepEqual(S([1: 2]), S([1: 2]))); // true
   
   and allowing:
   
   struct S {
     mixin(OpEquals);
     int[int] _m;
   }
   
   to give:
   
   	writeln(S([1: 2]) == S([1: 2]));  // now true false
   
   Provides other mixins like: OpEquals, PostBlit, OpCmp, Dup, Deep, ToHash, 
   HashSupport
*/

module opmix.mix;

public import opmix.dup;
import std.algorithm;
import std.math;
import std.string;
import std.traits;

/**
   Set this to true to see what is going on at compile time
*/
const(bool) LogCompile = false;

const(string) OpEquals = `
bool opEquals(const ref typeof(this) other) const {
  mixin(LogInfo("opEquals by ref ", "typeof(this)", "this"));
  return typesDeepEqual(this, other);
}

bool opEquals(const typeof(this) other) const {
  mixin(LogInfo("opEquals by val ", "typeof(this)", "this"));
  return typesDeepEqual(this, other);
}
`
;

/**
   Mixin to provide reasonable opCmp. It deeply compares the fields of
   the struct and assumes member structs have suitable opCmp. Use
   this, for example, to enable storing instances in a RedBlackTree.
*/
const(string) OpCmp = `
int opCmp(const ref typeof(this) other) const {
  return typesDeepCmp(this, other);
}

int opCmp(const typeof(this) other) const {
  return typesDeepCmp(this, other);
}
`
;

/**
   Mixin to provide a reasonable dup. dup is not really part of the
   language but rather a convention used to copy items that have
   aliasing/sharing. For example, dynamic arrays, associative,
   BitArray, HTTP have dup defined since a basic assignment of them
   introduces sharing. So if you want your class to have aliasing but
   still want an out mixin(Dup) and don't bother with mixin(PostBlit).
*/
const(string) Dup = `

  @property auto idup() const {
    return cast(immutable(typeof(this)))this.dup;
  }

  @property auto dup() const {
    Unqual!(typeof(this)) temp;
    gdup(temp, this);
    return temp;
  }
`;

/**
   Mixin to provide both a post blit and opEquals which usually go
   together.
*/
const(string) Deep = `
  mixin(PostBlit);
  mixin(OpEquals);
`;

/**
   Mixin to provide a this(this). This is very similar to dup in that
   it calls dup on all dupable fields of the struct. Decide up front
   if you want deep semantics (i.e. assignment will make deep copies
   of all members) on your struct. If you do, use this to get
   that. This is only useful if one or more of your fields require
   deep copy (like associative arrays, arrays, other classes with
   dup). If you are ok with shallow semantics, forego this and
   consider using mixin(Dup) to allow for deep copy. If you decide to
   go the PostBlit route, you probably need an opEquals with deep
   comparison. So consider mixin(DeepSemantics) wich includes
   mixin(PostBlit) and mixin(OpEquals).
*/
const(string) PostBlit = `
this(this) {
    alias typeof(this) T;
    foreach (i, field ; typeof(T.tupleof)) {
      alias typeof(T.tupleof[i]) FieldType;
      static if(isDynamicArray!(FieldType) &&
                isArrayOfImmutable!FieldType) {
        static if(LogCompile) 
          pragma(msg, 
                 "CT: No needless duping of immutable element type arr ", 
                 T.tupleof[i]); 
      } else static if(isPointer!(FieldType) || 
                       isDynamicArray!(FieldType) ||
                       isAssociativeArray!(FieldType) ||
                       HasDup!FieldType) {
        gdup(this.tupleof[i], this.tupleof[i]);
      } else static if(hasAliasing!FieldType) {
        static if(LogCompile) 
          pragma(msg, 
                 "CT: Postblit of ", T, " drilling down on ", 
                 T.tupleof[i].stringof);
        gdup(this.tupleof[i], this.tupleof[i]);
      } else {
        static if(LogCompile) 
          pragma(msg, 
                 "CT: Postblit of ", T, " ignoring ", 
                 T.tupleof[i].stringof);
      }
    }
  }
`;

/**
   Mixin to provide toHash for a struc that incorporates some aspect of all
   fields to the function.
*/
const(string) ToHash = `
  /**
    Hashing function hitting all data - mileage may vary.
    TODO: Make this and deepHash pure when foreach iteration permits
   */
  hash_t toHash() const nothrow {
    return deepHash!(typeof(this))(this);
  }
`;

/**
   Mixin to provide hashing functionality on a struct. For example, to
   make your struct usable as a key in an associative array you need
   to provide suitable and consistent toHash, opCmp, and
   opEquals. This mixin pulls in all three.
   
   According to the language spec: 
   
   'The implementation may use either opEquals or opCmp or both. Care
   should be taken so that the results of opEquals and opCmp are
   consistent with each other when the class objects are the same or
   not.'
   
   It is not clear whether that means you can leave opCmp out and it
   is capable of using opEquals alone... I had trouble there, so both
   are pulled in.
   
   In terms of performance, the point of the hash function is to get a
   good distribution. This implementation may be very expensive to
   compute compared to other custom hashes and it may not provide a
   good distribution. But you should be able to store HashSupport
   structs in a hash.
*/
const(string) HashSupport = `
  mixin(OpEquals);
  mixin(OpCmp);
  mixin(ToHash);
`;


// custom <dmodule mix public_section>

/** 
  For debugging, logs a compile time message at various points. If mixing in
  OpEquals or hashing and there are compile errors, maybe something in the
  struct is missing. The compile time logs help determine at what stage
  compilation goes off the rails.  To enable set LogCompile to true.
*/
string LogInfo(string tag, string T, string instance) { 
  return `
  static if(LogCompile) {
    pragma(msg, "CT: `~tag~`", `~T~`);
  }
  `;
}

/** Discriminates a pass type by its size
 */
template PrefersPassByRef(T) {
  static if(T.sizeof > 16 || hasAliasing!T) {
    enum PrefersPassByRef = true;
  } else {
    enum PrefersPassByRef = false;
  }
}

/** Discriminates a pass type by its size
 */
template PreferredPassType(T) {
  static if(PrefersPassByRef!T) {
    enum PreferredPassType = `const ref `~T.stringof;
  } else {
    enum PreferredPassType = T.stringof;
  }
}

/** Provides mixin for making a field read only.
 *  For example mixin(ReadOnly!_fieldName) provides a getter named fieldName.
 */
template ReadOnly(alias name) {
  enum v = name.stringof;
  enum p = name.stringof[1..$];
  enum prefersReference = PrefersPassByRef!(typeof(name));
  static if(prefersReference) {
    enum ReadOnly = `
public @property auto `~p~`() const { 
  return `~v~`; 
}
`;
  } else {
    enum ReadOnly = `
public @property ref auto `~p~`() const { 
  return `~v~`; 
}
`;
  }
}

/** Provides mixin for the *read* accessor when making a field read/write.
 * Don't be a liar - provide your own write accessor.
 */
template ReadWrite(alias name) {
  enum ReadWrite = ReadOnly!name;
}

/** Compare for equality all fields in a class
    Original courtesy of Tobias Pankrath
    Updated to use tupleof instead of getMember and short circuits
    Supports associative and dynamic arrays
    Treats default float.init as equal
 */
bool typesDeepEqual(T,F)(auto ref T lhs, auto ref F rhs)
  if(is(DeepUnqual!T == DeepUnqual!F)) {
  mixin(LogInfo("typesDeepEqual by ref ", "T", "lhs"));
  bool result = true;

  if(lhs is rhs) { return true; }

  static if(isFloatingPoint!(T)) {
    mixin(LogInfo("...typesDeepEqual floating ", "T", "lhs"));
    if(!isnan(lhs) || !isnan(rhs)) {
        result &= lhs == rhs;  
    }
    // both nan, assume equal - maybe should make configurable
  } else static if(isPointer!(T)) {
    mixin(LogInfo("...typesDeepEqual pointer ", "T", "lhs"));
    if(lhs && rhs) {
      result &= typesDeepEqual(*lhs, *rhs);
    } else {
      result = !(lhs || rhs);
    }
  } else static if(isAssociativeArray!(T)) {
    mixin(LogInfo("...typesDeepEqual assoc array ", "T", "lhs"));

    ///// TODO: Remove const casts on length and keys when no longer
    ///// necessary. Note: important to cast away const on both key and
    ///// value.
    alias KeyType!(T) AAKeyType;
    alias ValueType!(T) AAValueType;
    alias Unqual!(AAValueType)[Unqual!(AAKeyType)] NoConstAssocArr;
    if((cast(NoConstAssocArr)lhs).length != (cast(NoConstAssocArr)rhs).length) return false;
    auto lhsKeys = (cast(NoConstAssocArr)lhs).keys;
    auto rhsKeys = (cast(NoConstAssocArr)rhs).keys;

    lhsKeys.sort;
    rhsKeys.sort;
    for(size_t i=0; i<lhsKeys.length; ++i) {
        if(!typesDeepEqual(lhsKeys[i], rhsKeys[i])) return false;
        const(AAValueType)* lvalue = lhsKeys[i] in lhs;
        const(AAValueType)* rvalue = rhsKeys[i] in rhs;
        if(!((lvalue && rvalue)? typesDeepEqual(*lvalue, *rvalue) : lvalue == rvalue)) return false;
    }
  } else static if(isDynamicArray!(T)) {
    mixin(LogInfo("...typesDeepEqual dynamic array ", "T", "lhs"));
    auto llen = lhs.length, rlen = rhs.length;
    auto end = min(llen, rlen);
    for(size_t i=0; i<end; ++i) {
      if(!typesDeepEqual(lhs[i], rhs[i])) return false;
    }
    result = llen == rlen;
  } else static if(is(T == struct)) {
    mixin(LogInfo("...typesDeepEqual struct ", "T", "lhs"));
    foreach (i, ignore ; typeof(T.tupleof)) {
      mixin(LogInfo("struct field <"~lhs.tupleof[i].stringof~">", "T.tupleof[i]", "lhs.tupleof[i]"));
      alias typeof(T.tupleof[i]) FieldType;
      static if(T.tupleof[i].stringof.endsWith(".this")) {
        // Skip if nested class
      } else {
        // Special case pointed out by Tobias
        static if(isPointer!FieldType && is(PointerTarget!FieldType == T)) {
          auto l = lhs.tupleof[i];
          auto r = rhs.tupleof[i];
          if((l && ((*l).tupleof[i] == rhs.tupleof[i])) &&
             (r && ((*r).tupleof[i] == lhs.tupleof[i]))) {
            // let it ride
          } else {
            result &= typesDeepEqual(l, r);
          }
        } else {
          result &= typesDeepEqual(lhs.tupleof[i], rhs.tupleof[i]);
        }
      }
      if(!result) return false;
    }
  } else {
    mixin(LogInfo("...typesDeepEqual catch-all ", "T", "lhs"));
    result = lhs == rhs;
  }
  return result;
}

int opCmpPreferred(T, F)(const ref T lhs, const ref F rhs) {
  static if(__traits(compiles, (lhs.opCmp(rhs)))) {
    return lhs.opCmp(rhs);
  } else {
    return typesDeepCmp(lhs, rhs);
  }
}

/** Compare all fields for suitable opCmp.
    Order will be that returned by T.tupleof
 */
int typesDeepCmp(T,F)(auto ref T lhs, auto ref F rhs)
  if(is(DeepUnqual!T == DeepUnqual!F)) {

  static if(isFloatingPoint!(T)) {
    if(isnan(lhs) && isnan(rhs)) { return 0; }
    return (lhs<rhs)? -1 : (lhs>rhs)? 1 : 0;
  } else static if(isSomeString!T) {
    return lhs.cmp(rhs);
  } else static if(is(T == struct)) {
      foreach (i, ignore ; typeof(T.tupleof)) {
        static if(T.tupleof[i].stringof.endsWith(".this")) {
          // Skip if nested class
        } else {
          int result = opCmpPreferred(lhs.tupleof[i], rhs.tupleof[i]);
          if(result) return result;
        }
      }
      return 0;
  } else static if(isPointer!(T)) {
      int result;
      if(lhs && rhs) {
        result = opCmpPreferred(*lhs, *rhs);
      } else {
        result = rhs? -1 : lhs? 1 : 0;
      }
      return result;
  } else static if(isAssociativeArray!(T)) {
    ///// TODO: Remove const casts on keys
    // Compare keys in order
    alias Unqual!(ValueType!T)[Unqual!(KeyType!T)] NoConstAssocArr;
    auto lhsKeys = (cast(NoConstAssocArr)lhs).keys.dup;
    auto rhsKeys = (cast(NoConstAssocArr)rhs).keys.dup;
    if(lhsKeys.length != rhsKeys.length) return false;

    lhsKeys.sort;
    rhsKeys.sort;

    auto keysCmp = cmp(lhsKeys, rhsKeys);
    if(keysCmp) { return keysCmp; }

    foreach(ref key; lhsKeys) {
      auto lhsVal = key in lhs;
      auto rhsVal = key in rhs;

      if(lhsVal && rhsVal) { 
        auto result = opCmpPreferred(*lhsVal, *rhsVal);
        if(result) return result;
      } else if(rhsVal) { 
        return -1;
      } else { 
        return 1;
      }
    }

    return 0;
  } else {
    return (lhs < rhs)? -1 : (lhs > rhs)? 1 : 0;
  }
}

hash_t toHashPreferred(T)(const ref T t) nothrow {
  static if(is(T==struct) && __traits(compiles, (t.toHash()))) {
    return t.toHash();
  } else {
    return deepHash(t);
  }
}

/**

  Computes a hash taking into account all fields. A good question in a long
  thread was posed here
  http://forum.dlang.org/post/jiweknaxeaeepjlvhrlf@forum.dlang.org

  This uses the same ideas and provides function to wrap as mixin.

 */
hash_t deepHash(T)(const ref T t) nothrow { 
  const int prime = 23;
  hash_t result = 17;
  static if(isPointer!T) {
    mixin(LogInfo("Hashing ptr ", "T", "t"));
    if(t) {
      result = result*prime + deepHash(*t);
    }
  } else static if(isAssociativeArray!T) {
    try {
      foreach(key, value; t) {
        mixin(LogInfo("Hashing assoc array ", "T", "t"));
        result = result*prime + deepHash(key);
        result = result*prime + deepHash(value);
      }
    } catch(Exception) {
      assert(0);
    }
  } else static if(isSomeString!(T)) {
    mixin(LogInfo("Hashing string ", "T", "t"));
    result = result*prime + typeid(T).getHash(&t);
  } else static if(isArray!T) {
    mixin(LogInfo("Hashing array ", "T", "t"));
    size_t end = t.length;
    for(size_t i=0; i<end; ++i) {
      result = result*prime + toHashPreferred(t[i]);
    }
  } else static if (isIntegral!(T) || isSomeChar!(T) || 
                    isBoolean!(T) || is(T==enum)) {
    mixin(LogInfo("Hashing integral, char, bool, enum ", 
                  "T", "t"));
    result = result*prime + t;
  } else static if (isFloatingPoint!(T)) {
    mixin(LogInfo("Hashing floating point ", "T", "t"));
    if(isnan(t)) { 
      result = result*prime + prime;
    } else {
      byte[T.sizeof] *buff = cast(byte[T.sizeof]*)&t;
      for(size_t i=0; i<T.sizeof; ++i) {
        result = result*prime + (*buff)[i];
      }
    }
  } else static if (is(T == struct) || is(T == class)) {
    mixin(LogInfo("Hashing struct ", "T", "t"));
    static if(is(T == class)) {
      if(!t) {
        return result;
      }
    } 
    foreach (i, ignore ; typeof(T.tupleof)) {
      static if(T.tupleof[i].stringof.endsWith(".this")) {
      } else {
        result = result*prime + toHashPreferred(t.tupleof[i]);
      }
    }
  } else {
    static assert(0, "Add support for "~T);
  }

  return result;
}

template HasDup(T) { 
  enum HasDup = __traits(hasMember, T, "dup"); 
}

template IsImmutable(T) { 
  static if(is(T U == immutable U)) {
    enum IsImmutable = true;
  } else {
    enum IsImmutable = false;
  }
}

// end <dmodule mix public_section>

/**
   License: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
*/
