type t = {
  id,
  serialNumber: string,
  createdAt: Js.Date.t,
  courseName: string,
}
and id = string;

let id = t => t.id;
let serialNumber = t => t.serialNumber;
let createdAt = t => t.createdAt;
let courseName = t => t.courseName;

let decode = json =>
  Json.Decode.{
    id: json |> field("id", string),
    serialNumber: json |> field("serialNumber", string),
    createdAt: json |> field("createdAt", string) |> DateFns.parseString,
    courseName: json |> field("courseName", string),
  };
