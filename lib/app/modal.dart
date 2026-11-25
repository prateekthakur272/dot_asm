import 'package:dot_asm/core/model/project.dart';
import 'package:dot_asm/core/sim/spec/processor_spec.dart';

/// Descriptors of the modal dialogs. `state.modal = ModalSettings()` shows one; `buildActiveModal` resolves each
/// case with an exhaustive pattern match.
sealed class AppModal {
  const AppModal();
}

class ModalSettings extends AppModal {
  const ModalSettings();
}

class ModalAbout extends AppModal {
  const ModalAbout();
}

class ModalDeveloper extends AppModal {
  const ModalDeveloper();
}

class ModalUpdateAvailable extends AppModal {
  const ModalUpdateAvailable(this.version);
  final String version;
}

class ModalNewProject extends AppModal {
  const ModalNewProject({this.templateId, this.openInBuilder = false});

  /// Preselected template.
  final String? templateId;

  /// Start with "open the processor in the builder" ticked (customising a template).
  final bool openInBuilder;
}

class ModalRenameProject extends AppModal {
  const ModalRenameProject(this.project);
  final Project project;
}

class ModalConfirmDeleteProject extends AppModal {
  const ModalConfirmDeleteProject(this.project);
  final Project project;
}

class ModalImportProcessor extends AppModal {
  const ModalImportProcessor();
}

class ModalConfirmDeleteProcessor extends AppModal {
  const ModalConfirmDeleteProcessor(this.processor);
  final ProcessorSpec processor;
}
