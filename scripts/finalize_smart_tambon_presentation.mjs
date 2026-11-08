import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const workspaceDir=path.resolve('.');
const skillDir='C:/Users/nutta/.codex/plugins/cache/openai-primary-runtime/presentations/26.1105.12137/skills/presentations';
const pythonExecutable='C:/Users/nutta/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe';
const candidatePath=path.join(workspaceDir,'presentation_output','System_Product_Presentation.pptx');
const finalPath=path.join(workspaceDir,'presentation_output','System_Product_Presentation_Final.pptx');
const { finalizePresentation }=await import(pathToFileURL(path.join(skillDir,'container_tools/artifact_tool_utils.mjs')).href);
const stagingDir=path.join(workspaceDir,'.codex-finalizer'); await fs.mkdir(stagingDir,{recursive:true});
const result=await finalizePresentation({
  workspaceDir,candidatePath,finalPath,pythonExecutable,
  integrityValidatorPath:path.join(skillDir,'container_tools/inspect_presentation_package_integrity.py'),
  layoutValidatorPath:path.join(skillDir,'container_tools/inspect_presentation_layout_geometry.py'),
  layoutArgs:['--expected-slide-size-emu','12192000,6858000','--validate-bullet-geometry','--validate-heading-fit'],
  explicitTotalSlideCount:15,requiredNativeTableOwnerSlides:[],requiredNativeChartOwnerSlides:[],
  fontPolicy:{basis:'design',families:['Arial']},verifyArtifactToolImport:true,
  receiptPath:path.join(stagingDir,'System_Product_Presentation_Final.pptx.validation.json')
});
console.log(JSON.stringify(result,null,2));
