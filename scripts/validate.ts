
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

/**
 * Extract {vendor} and {code} from npm package name.
 * Pattern: @zerobias-org/schema-{vendor}-{code}
 * The vendor is always the first segment after "schema-", code is the rest joined.
 * Examples:
 *   @zerobias-org/schema-github-github → { vendor: 'github', code: 'github' }
 *   @zerobias-org/schema-w3geekery-smemart → { vendor: 'w3geekery', code: 'smemart' }
 *   @zerobias-org/schema-zerobias-zerobias-base → { vendor: 'zerobias', code: 'zerobias-base' }
 */
function extractVendorCode(packageName: string): { vendor: string; code: string } | null {
  const match = packageName.match(/^@zerobias-org\/schema-([^-]+)-(.+)$/);
  if (!match) return null;
  return { vendor: match[1], code: match[2] };
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
    // Skip further validation for deprecated packages
    if (zerobias.deprecated === true) {
      return;
    }

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

/**
 * Cross-validate naming consistency across package.json, catalog.yml, and directory path.
 *
 * All identifiers must use the same {vendor} and {code} segments:
 *   - npm package name: @zerobias-org/schema-{vendor}-{code}
 *   - catalog.yml package: {vendor}.{code}.schema
 *   - directory: package/{vendor}/{code}/
 *   - product dependency: @zerobias-org/product-{vendor}-{code}
 *   - zerobias.package: {vendor}.{code}.schema
 *
 * This prevents the artifact/product mismatch that causes the dataloader to fail
 * to associate classes with their product (e.g., sme-mart vs smemart).
 */
function validateNamingConsistency(
  packageFile: Record<string, any>,
  catalogFile: Record<string, any>,
  directory: string
): void {
  const zerobias = packageFile.zerobias ?? packageFile.auditmation;

  // Skip for deprecated packages
  if (zerobias?.deprecated === true) {
    console.log('  Skipping naming consistency check (deprecated package)');
    return;
  }

  const parsed = extractVendorCode(packageFile.name);
  if (!parsed) {
    throw new Error(
      `Cannot parse vendor/code from package name "${packageFile.name}". ` +
      `Expected format: @zerobias-org/schema-{vendor}-{code}`
    );
  }

  const { vendor, code } = parsed;
  const errors: string[] = [];

  // Validate vendor and code match ^[a-z0-9]+$ (ZB platform vspCodeValidator constraint)
  const codePattern = /^[a-z0-9]+$/;
  if (!codePattern.test(vendor)) {
    errors.push(
      `Vendor code "${vendor}" contains invalid characters. ` +
      `Must match ^[a-z0-9]+$ (lowercase alphanumeric only — no hyphens, underscores, or dots).`
    );
  }
  if (!codePattern.test(code)) {
    errors.push(
      `Schema code "${code}" contains invalid characters. ` +
      `Must match ^[a-z0-9]+$ (lowercase alphanumeric only — no hyphens, underscores, or dots).`
    );
  }

  // Check catalog.yml package matches
  const expectedCatalogPackage = `${vendor}.${code}.schema`;
  const actualCatalogPackage = catalogFile.Schema?.package;
  if (actualCatalogPackage && actualCatalogPackage !== expectedCatalogPackage) {
    errors.push(
      `catalog.yml package "${actualCatalogPackage}" does not match expected "${expectedCatalogPackage}" ` +
      `(derived from npm package name "${packageFile.name}")`
    );
  }

  // Check zerobias.package matches catalog
  const zbPackage = zerobias?.package;
  if (zbPackage && zbPackage !== expectedCatalogPackage) {
    errors.push(
      `package.json zerobias.package "${zbPackage}" does not match expected "${expectedCatalogPackage}"`
    );
  }

  // Check directory path matches
  const resolvedDir = path.resolve(directory);
  const dirParts = resolvedDir.split(path.sep);
  const dirCode = dirParts[dirParts.length - 1];
  const dirVendor = dirParts[dirParts.length - 2];

  if (dirVendor !== vendor) {
    errors.push(
      `Directory vendor "${dirVendor}" does not match package vendor "${vendor}". ` +
      `Directory should be package/${vendor}/${code}/`
    );
  }
  if (dirCode !== code) {
    errors.push(
      `Directory code "${dirCode}" does not match package code "${code}". ` +
      `Directory should be package/${vendor}/${code}/`
    );
  }

  // Check product dependency matches
  const expectedProductDep = `@zerobias-org/product-${vendor}-${code}`;
  const deps = packageFile.dependencies || {};
  const hasMatchingProduct = Object.keys(deps).some(dep => dep === expectedProductDep);
  if (Object.keys(deps).length > 0 && !hasMatchingProduct) {
    // Check if there's a product dep with a DIFFERENT code (the mismatch we're catching)
    const productDeps = Object.keys(deps).filter(d => d.startsWith('@zerobias-org/product-'));
    if (productDeps.length > 0) {
      const actualProductDep = productDeps[0];
      if (actualProductDep !== expectedProductDep) {
        errors.push(
          `Product dependency "${actualProductDep}" does not match expected "${expectedProductDep}". ` +
          `The {code} segment must be identical across npm package, product, catalog, and directory.`
        );
      }
    }
  }

  // Check for hyphens in code segment (common source of mismatch)
  // The code in the npm package name becomes the product code, which must not have hyphens
  // in the catalog package (dots are used as separators: vendor.code.schema)
  if (actualCatalogPackage) {
    const catalogParts = actualCatalogPackage.split('.');
    if (catalogParts.length >= 2) {
      const catalogCode = catalogParts[1];
      // If npm code has hyphens but catalog code doesn't, flag it
      if (code.includes('-') && !catalogCode.includes('-') && code.replace(/-/g, '') === catalogCode) {
        errors.push(
          `Naming mismatch: npm package uses hyphenated code "${code}" but catalog uses "${catalogCode}". ` +
          `These must match exactly. Either rename the npm package to use "${catalogCode}" or ` +
          `update the catalog to use "${code}". Recommendation: avoid hyphens in the code segment.`
        );
      }
    }
  }

  if (errors.length > 0) {
    throw new Error(
      `Naming consistency check failed:\n${errors.map(e => `  - ${e}`).join('\n')}\n\n` +
      `All identifiers must use the same {vendor} and {code}:\n` +
      `  npm package:  @zerobias-org/schema-{vendor}-{code}\n` +
      `  catalog.yml:  {vendor}.{code}.schema\n` +
      `  directory:    package/{vendor}/{code}/\n` +
      `  product dep:  @zerobias-org/product-{vendor}-{code}\n` +
      `  zb.package:   {vendor}.{code}.schema`
    );
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

  // Cross-validate naming consistency
  validateNamingConsistency(packageJson, catalogYml, directory);
  console.log('Validated naming consistency');

  // Validate .npmrc
  const checkNpmrc = await fs.lstat(path.join(directory, '.npmrc'))
    .catch(() => undefined);

  if (!checkNpmrc || !checkNpmrc.isFile()) {
    throw new Error(`.npmrc file not found or is not file in directory: ${directory}`);
  }

  console.log('Validated .npmrc');

  // Check for at least one of classes/, interfaces/, or fields/
  // (skip for deprecated packages)
  const zerobias = packageJson.zerobias ?? packageJson.auditmation;
  if (zerobias?.deprecated !== true) {
    const hasClasses = await fs.lstat(path.join(directory, 'classes')).catch(() => undefined);
    const hasInterfaces = await fs.lstat(path.join(directory, 'interfaces')).catch(() => undefined);
    const hasFields = await fs.lstat(path.join(directory, 'fields')).catch(() => undefined);

    if (!hasClasses && !hasInterfaces && !hasFields) {
      throw new Error('Schema package must contain at least one of: classes/, interfaces/, or fields/ directories');
    }
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
