// Generate an empty table-capable donor from a separately acquired MIT fixture.
// No original Nashi code or document is read by this build step.
import fs from "node:fs";
import { PagesDocument } from "../Tools/PagesBuild/cupertino/package/dist/pages/document.js";
import { ZipReader, buildZip } from "../Tools/PagesBuild/cupertino/package/dist/base/zip.js";
const document = PagesDocument.blankFrom(fs.readFileSync(new URL("../Tools/PagesBuild/picodocs-sample.pages", import.meta.url)));
for (const storage of document.textStorages()) storage.setText("");
for (const table of document.tables()) {
  for (const merge of table.merges()) table.unmergeCells(merge.row, merge.column);
  table.clearAllCells();
  table.setBands({headerRows: 0, headerColumns: 0, footerRows: 0});
  table.nameVisible = false;
}
document.setPageSetup({pageWidth: 595.28, pageHeight: 841.89, leftMargin: 56.69, rightMargin: 56.69, topMargin: 56.69, bottomMargin: 56.69});
const zip = ZipReader.parse(document.save());
const entries = zip.entries.filter(entry => !entry.isDirectory && !/^preview|^Data\//.test(entry.name));
fs.writeFileSync(new URL("../Tools/PagesBuild/table-seed.pages", import.meta.url), buildZip(entries.map(entry => ({name:entry.name, data:zip.read(entry)}))));
