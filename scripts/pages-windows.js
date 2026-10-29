// Same audited Pages bundle as macOS. Deno receives only exact input/output paths.
const [bundle, mode, input, output] = Deno.args;
if (!['read', 'write'].includes(mode)) throw new Error('Invalid Pages operation');
const runtime = new Function((await Deno.readTextFile(bundle)) + ';return NashiPages;')();
if (mode === 'read') {
  const bytes = await Deno.readFile(input);
  let binary = '';
  for (let i=0;i<bytes.length;i+=8192) binary += String.fromCharCode(...bytes.subarray(i,i+8192));
  await Deno.writeTextFile(output, runtime.read(btoa(binary)));
} else {
  const binary = atob(runtime.write(await Deno.readTextFile(input)));
  await Deno.writeFile(output, Uint8Array.from(binary,c=>c.charCodeAt(0)));
}
