package func xcodeProjectSource(
  targetSettings: String = "SWIFT_VERSION = 5.0;",
  projectMode: String = "6.0"
) -> String {
  """
  {
    rootObject = project;
    objects = {
      project = { isa = PBXProject; targets = (app); buildConfigurationList = projectList; };
      app = { isa = PBXNativeTarget; buildConfigurationList = targetList; };
      projectList = { buildConfigurations = (projectDebug); };
      targetList = { buildConfigurations = (targetDebug); };
      projectDebug = { name = Debug; buildSettings = { SWIFT_VERSION = \(
        projectMode
      ); }; };
      targetDebug = { name = Debug; buildSettings = { \(targetSettings) }; };
    };
  }
  """
}
