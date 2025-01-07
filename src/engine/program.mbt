///|
trait Device: Show {
  allocate(Self, Int) -> Int
}

///|
pub enum Schedule[Value, Compute] {
  Const(Value)
  Apply(Compute, Array[Value])
}
