import axios from "axios";

export async function readAddressBook(contractVersion: string = "stable") {
  const { data: addressBook } = await axios.get(
    `https://sc-abis.s3.us-east-2.amazonaws.com/${contractVersion}/addressbook.json`,
  );
  return addressBook;
}
