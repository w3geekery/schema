
import fs from 'fs/promises';
import path from 'path';
import yaml from 'yaml';
import { UUID } from '@zerobias-org/types-core-js';

function isKnownFileType(filename: string): boolean {
  return (filename.toLowerCase().endsWith('.yml') || filename.toLowerCase().endsWith('.json'));
}

async function readAndParseFile(file: string, fullPathFile: string): Promise<any> {
  if (isKnownFileType(file)) {
    const fileData = (await fs.readFile(fullPathFile)).toString();

    let name = file;

    if (name.indexOf('/') !== -1) {
      name = name.substring(name.lastIndexOf('/') + 1);
    }

    name = name.substring(0, name.lastIndexOf('.'));

    let document = null;

    if (file.endsWith('.yml')) {
      document = yaml.parse(fileData);
    } else if (file.endsWith('.json')) {
      document = JSON.parse(fileData);
    }

    return document;
  }

  throw new Error(`File type not supported: ${file}`);
}

function processPackageJson(packageFile: Record<string, any>): void {
  const namePattern = /^@zerobias-org\/schema-.+$/;
  if (!packageFile.name || !namePattern.test(packageFile.name)) {
    throw new Error('package.json name must match @zerobias-org/schema-<vendor>-<code>');
  }

  if (!packageFile.description || packageFile.description === '{name}') {
    throw new Error('package.json missing description or needs replacement from {name}');
  }

  const zerobias = packageFile.zerobias ?? packageFile.auditmation;
  if (zerobias && typeof zerobias === 'object') {
    if (zerobias['import-artifact'] !== 'schema') {
      throw new Error('package.json zerobias section import-artifact must be "schema"');
    }
    if (!zerobias.package) {
      throw new Error('package.json zerobias section missing package');
    }
    if (!zerobias['dataloader-version']) {
      throw new Error('package.json zerobias section missing dataloader-version');
    }
  } else {
    throw new Error('package.json missing zerobias (or auditmation) section');
  }
}

async function processCatalogYml(catalogFile: Record<string, any>): Promise<void> {
  if (!catalogFile.Schema) {
    throw new Error('catalog.yml missing Schema section');
  }

  const schema = catalogFile.Schema;
  if (!schema.name || schema.name === '{name}') {
    throw new Error('catalog.yml Schema.name needs replacement from {name}');
  }
  if (!schema.package || schema.package === '{vendor}.{code}.schema') {
    throw new Error('catalog.yml Schema.package needs replacement');
  }
  if (!schema.description || schema.description === '{description}') {
    throw new Error('catalog.yml Schema.description needs replacement from {description}');
  }
}

async function processArtifact(directory: string) {
  const checkDir = await fs.lstat(directory)
    .catch(() => undefined);

  if (!checkDir || !checkDir.isDirectory()) {
    throw new Error(`Path given is not found or not a directory: ${directory}`);
  }

  // Validate package.json
  const checkPackageJson = await fs.lstat(path.join(directory, 'package.json'))
    .catch(() => undefined);

  if (!checkPackageJson || !checkPackageJson.isFile()) {
    throw new Error(`package.json file not found or is not file in directory: ${directory}`);
  }

  const packageJson = await readAndParseFile('package.json', path.join(directory, 'package.json'));
  if (!packageJson) {
    throw new Error('Unable to parse package.json');
  }

  processPackageJson(packageJson);
  console.log('Validated package.json');

  // Validate catalog.yml
  const checkCatalogYml = await fs.lstat(path.join(directory, 'catalog.yml'))
    .catch(() => undefined);

  if (!checkCatalogYml || !checkCatalogYml.isFile()) {
    throw new Error(`catalog.yml file not found or is not file in directory: ${directory}`);
  }

  const catalogYml = await readAndParseFile('catalog.yml', path.join(directory, 'catalog.yml'));
  if (!catalogYml) {
    throw new Error('Unable to parse catalog.yml');
  }

  await processCatalogYml(catalogYml);
  console.log('Validated catalog.yml');

  // Validate .npmrc
  const checkNpmrc = await fs.lstat(path.join(directory, '.npmrc'))
    .catch(() => undefined);

  if (!checkNpmrc || !checkNpmrc.isFile()) {
    throw new Error(`.npmrc file not found or is not file in directory: ${directory}`);
  }

  console.log('Validated .npmrc');

  // Check for at least one of classes/, interfaces/, or fields/
  const hasClasses = await fs.lstat(path.join(directory, 'classes')).catch(() => undefined);
  const hasInterfaces = await fs.lstat(path.join(directory, 'interfaces')).catch(() => undefined);
  const hasFields = await fs.lstat(path.join(directory, 'fields')).catch(() => undefined);

  if (!hasClasses && !hasInterfaces && !hasFields) {
    throw new Error('Schema package must contain at least one of: classes/, interfaces/, or fields/ directories');
  }

  console.log('Validated schema directories');
}

(async () => {
  try {
    const directory = './';
    await processArtifact(directory);
    console.log('Validation of artifact completed successfully.');
    process.exit(0);
  } catch (error: any) {
    console.error(`Validation failed \n${error.message}\n${JSON.stringify(error.stack)}`);
    process.exit(1);
  }
})();
