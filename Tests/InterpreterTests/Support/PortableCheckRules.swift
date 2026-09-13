import Bylaws
import Testing

func sharedPackageCheck(_ codebase: Codebase) async throws
  -> PackageDependencyCheck
{
  try await codebase.checkPackageDependencies()
}

func sharedStabilityCheck(_ codebase: Codebase) async throws
  -> DependencyStabilityCheck
{
  try await codebase.checkDependencyStability()
}

func sharedLayeringCheck(
  _ codebase: Codebase,
  _ layers: Layering
) async throws -> LayeringCheck {
  try await codebase.checkLayering(layers)
}

func sharedResultFields(_ codebase: Codebase) async throws
  -> Violations<SourceFile>
{
  let check = try await codebase.checkPackageDependencies()
  let files = try await codebase.files
  guard let location = files.first?.location else {
    return files
      .violations(of: Matcher<SourceFile>("have a source location") { _ in
        false
      })
  }
  let findings = check.findings(reportedAt: location)
  let repeated = findings.findings(reportedAt: location)
  let importFindings = check.violations.findings(reportedAt: location)
  let countsAgree = findings.violations.count == findings.violations.offenders
    .count
    && check.violations.count == check.undeclared.count
    && check.violations.offenders.allSatisfy { !$0.moduleName.isEmpty }
    && repeated.violations == findings.violations
    && repeated.warnings == findings.warnings
    && importFindings.violations.count == check.undeclared.count
    && importFindings.warnings.isEmpty
  let warningsHaveLocations = findings.warnings.allSatisfy {
    !$0.message.isEmpty && $0.location.line > 0 && !$0.location.filePath.isEmpty
  }
  return files
    .violations(
      of: Matcher<SourceFile>("return consistent check results") { _ in
        countsAgree && warningsHaveLocations
      }
    )
}
