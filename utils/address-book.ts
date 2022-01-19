import { resolve, join } from "path";
import { readJSON, outputJSON } from "fs-extra";

export async function addToAddressBook(contractName: string, address: string) {
  const addressBookDir = resolve(__dirname, "..");
  const addressBookPath = join(addressBookDir, "addressbook.json");
  let addressBook;
  try {
    addressBook = await readJSON(addressBookPath);
  } catch (err) {
    addressBook = {};
  }
  addressBook[contractName] = address;
  await outputJSON(addressBookPath, addressBook, { spaces: 2 });
}
