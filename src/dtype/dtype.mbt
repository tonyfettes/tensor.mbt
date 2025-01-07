///|
enum DtypeValue {
  I32(Int)
  F32(Float)
}

///|
enum DtypeArray {
  I32(FixedArray[Int])
  F32(FixedArray[Float])
}

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
pub(all) enum Dtype {
  I32
  F32
}

///|
pub fn DtypeArray::dtype(self : DtypeArray) -> Dtype {
  match self {
    I32(_) => I32
    F32(_) => F32
  }
}

///|s
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
