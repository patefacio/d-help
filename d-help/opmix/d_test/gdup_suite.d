module opmix.d_test.gdup_suite;

import dunit;
import opmix.mix;
import std.algorithm;
import std.math;
import std.stdio;
import std.string;
import std.traits;

class MultiLevelRefCluct { 
  mixin TestMixin;
  static struct A { 
    char[] c;
  }

  static struct B { 
    A a;
  }

  static struct C { 
    B b;
  }


  void testDeepDup() {
  
// custom <multi_level_ref_clucttest_deep_dup>

    const(C) c = C(B(A(['a'])));
    C c2 = c.gdup;
    assert(0==typesDeepCmp(c,c2));
    assertNotEquals(c.b.a.c.ptr, c2.b.a.c.ptr);

// end <multi_level_ref_clucttest_deep_dup>
  }
}

class CustomDupCalled { 
  mixin TestMixin;
  static struct A { 
    char[] c;
    static bool dupHasBeenCalled;
    
// custom <dstruct a public_section>

    @property A dup() const {
      A a;
      a.c = c.dup;
      dupHasBeenCalled = true;
      return a;
    }

// end <dstruct a public_section>
  }

  static struct B { 
    A a;
    static bool dupHasBeenCalled;
    
// custom <dstruct b public_section>

    @property B dup() const {
      B b;
      b.a = a.dup;
      dupHasBeenCalled = true;
      return b;
    }

// end <dstruct b public_section>
  }

  static struct C { 
    B b;
    
// custom <dstruct c public_section>
// end <dstruct c public_section>
  }


  void testCustomDupCalled() {
  
// custom <custom_dup_calledtest_custom_dup_called>

    const(C) c = C(B(A(['a'])));
    A.dupHasBeenCalled = B.dupHasBeenCalled = false;
    C c2 = c.gdup;
    assert(0==typesDeepCmp(c,c2));
    assertNotEquals(c.b.a.c.ptr, c2.b.a.c.ptr);
    assert(A.dupHasBeenCalled);
    assert(B.dupHasBeenCalled);

// end <custom_dup_calledtest_custom_dup_called>
  }
}


void main() {
  dunit.runTests_Tree();
}


// custom <dmodule gdup_suite public_section>
// end <dmodule gdup_suite public_section>

/**
   License: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
*/
