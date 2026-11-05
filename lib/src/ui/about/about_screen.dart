import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../controllers/app_controller.dart';

/// Port of the About pane (`index.html` `#screen-about`).
///
/// The software bill of materials table is replaced by Flutter's
/// [showLicensePage], which lists the packages this build actually ships.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, required this.app});

  final AppController app;

  static const String _description =
      'Simplex blender plans gas fills around your leftover cylinders and '
      'the pressure you need in the water rather than a mixing station\'s '
      'menu, treating temperature as a blending parameter as important as '
      'composition, so you can see what the tank goes through while filling '
      'and reduce its thermal stress.';

  static const List<_AboutLink> _socialLinks = <_AboutLink>[
    _AboutLink(label: 'GitHub', url: 'https://github.com/speleobrad'),
    _AboutLink(label: 'Instagram', url: 'https://www.instagram.com/speleobrad'),
    _AboutLink(label: 'Facebook', url: 'https://www.facebook.com/speleobrad'),
  ];

  static const List<_AboutLink> _feedbackLinks = <_AboutLink>[
    _AboutLink(
      label: 'Report a bug',
      url:
          'https://github.com/speleobrad/simplex-blender/issues/new'
          '?labels=bug',
    ),
    _AboutLink(
      label: 'Request a feature',
      url:
          'https://github.com/speleobrad/simplex-blender/issues/new'
          '?labels=enhancement',
    ),
    _AboutLink(
      label: 'Browse open issues',
      url: 'https://github.com/speleobrad/simplex-blender/issues',
    ),
  ];

  static const String _applicationName = 'Simplex blender';
  static const String _license = 'GPL-3.0-only';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 768),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'About Simplex blender',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        const Text('Made with curiosity by Speleobrad.'),
                        const SizedBox(height: 8),
                        Text(
                          _description,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          children: <Widget>[
                            for (final link in _socialLinks)
                              _LinkButton(link: link),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Bugs and feature requests',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        for (final link in _feedbackLinks)
                          _LinkButton(link: link),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Open-source licenses',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Simplex blender itself is $_license. Third-party '
                          'components are listed in the license page.',
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton(
                            onPressed: () => showLicensePage(
                              context: context,
                              applicationName: _applicationName,
                              applicationLegalese: _license,
                            ),
                            child: const Text('Open-source licenses'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Simplex blender is free software, licensed under '
                  '$_license.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AboutLink {
  const _AboutLink({required this.label, required this.url});

  final String label;
  final String url;
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.link});

  final _AboutLink link;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () =>
          launchUrl(Uri.parse(link.url), mode: LaunchMode.externalApplication),
      child: Text(link.label),
    );
  }
}
