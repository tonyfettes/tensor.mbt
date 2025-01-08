///|
enum DtypeValue {
  I32(Int)
  F32(Float)
}

///|
pub enum DtypeArray {
  I32(FixedArray[Int])
  F32(FixedArray[Float])
} derive(Show, Eq)

///|
pub impl Hash for DtypeArray with hash_combine(self : DtypeArray, hasher : Hasher) -> Unit {
  match self {
    I32(array) =>
      for value in array {
        hasher.combine(value)
      }
    F32(array) =>
      for value in array {
        hasher.combine(value)
      }
  }
}

///|
enum Dtype {
  I32
  F32
} derive(Show)

///|
pub fn DtypeArray::new(dtype : Dtype, length : Int) -> DtypeArray {
  match dtype {
    I32 => I32(FixedArray::make(length, 0))
    F32 => F32(FixedArray::make(length, 0.0))
  }
}

///|
pub fn DtypeArray::i32(value : FixedArray[Int]) -> DtypeArray {
  I32(value)
}

///|
pub fn DtypeArray::f32(value : FixedArray[Float]) -> DtypeArray {
  F32(value)
}

///|
pub impl ToJson for DtypeArray with to_json(self : DtypeArray) -> Json {
  match self {
    I32(value) => value.to_json()
    F32(value) => value.to_json()
  }
}

///|
pub trait ToDtypeArray {
  to_dtype_array(FixedArray[Self]) -> DtypeArray
}

///|
pub impl ToDtypeArray for Int with to_dtype_array(self : FixedArray[Int]) -> DtypeArray {
  I32(self)
}

///|
pub impl ToDtypeArray for Float with to_dtype_array(self : FixedArray[Float]) -> DtypeArray {
  F32(self)
}

///|
pub fn DtypeArray::dtype(self : DtypeArray) -> Dtype {
  match self {
    I32(_) => I32
    F32(_) => F32
  }
}

///|
trait ToDtypeValue {
  to_dtype_value(Self) -> DtypeValue
}

///|
impl ToDtypeValue for Int with to_dtype_value(self : Int) -> DtypeValue {
  I32(self)
}

///|
impl ToDtypeValue for Float with to_dtype_value(self : Float) -> DtypeValue {
  F32(self)
}

///|
pub trait ToDtype {
  dtype() -> Dtype
}

///|
impl ToDtype for Int with dtype() -> Dtype { I32 }

///|
pub impl ToDtype for Float with dtype() -> Dtype { F32 }
