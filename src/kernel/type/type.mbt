///|
enum Type {
  I32
  F32
  Ptr(Type)
} derive(Eq, Hash)

///|
pub let i32 : Type = Type::I32

///|
pub let ptr_i32 : Type = Type::Ptr(I32)

///|
pub let f32 : Type = Type::F32

///|
pub let ptr_f32 : Type = Type::Ptr(F32)

///|
pub impl Show for Type with output(self : Type, logger : &Logger) -> Unit {
  match self {
    I32 => logger.write_string("i32")
    F32 => logger.write_string("f32")
    Ptr(ty) => {
      logger.write_string("ptr(")
      ty.output(logger)
      logger.write_string(")")
    }
  }
}

///|
pub impl ToJson for Type with to_json(self : Type) -> Json {
  match self {
    I32 => "i32"
    F32 => "f32"
    Ptr(self) => { "ptr": self.to_json() }
  }
}

///|
enum TypedImmutArray {
  I32(@immut/array.T[Int])
  F32(@immut/array.T[Float])
} derive(Hash, Eq)

///|
pub trait FixedToImmut {
  to_immut(FixedArray[Self]) -> TypedImmutArray
}

///|
pub impl FixedToImmut for Int with to_immut(self : FixedArray[Int]) -> TypedImmutArray {
  I32(@immut/array.from_iter(self.iter()))
}

///|
pub impl FixedToImmut for Float with to_immut(self : FixedArray[Float]) -> TypedImmutArray {
  F32(@immut/array.from_iter(self.iter()))
}
