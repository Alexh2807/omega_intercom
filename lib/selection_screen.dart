import 'package:flutter/material.dart';

class SelectionScreen extends StatelessWidget {
  const SelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Utilise MediaQuery pour rendre le design adaptable à différentes tailles d'écran
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        // Utilise la couleur primaire du thème pour la barre d'applications
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        title: const Text(
          'Choisissez votre modèle',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          // Ajoute une marge horizontale pour ne pas coller les bords de l'écran
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: ConstrainedBox(
            // Limite la largeur maximale de la carte sur les grands écrans
            constraints: const BoxConstraints(maxWidth: 500),
            child: Card(
              elevation: 8.0, // Ajoute une ombre portée pour un effet de profondeur
              clipBehavior: Clip.antiAlias, // Assure que l'image ne dépasse pas les coins arrondis
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15.0),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min, // La carte prend la taille de son contenu
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Affiche l'image de la moto depuis les assets
                  Image.asset(
                    'assets/images/motorcycle1.png',
                    fit: BoxFit.cover,
                    height: 250, // Hauteur fixe pour l'image
                  ),

                  // Ajoute un espace entre l'image et le texte
                  const SizedBox(height: 16),

                  // Titre du modèle
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      'Omega Intercom v1',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  // Description du modèle
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Text(
                      'Le système de communication nouvelle génération pour tous vos trajets.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ),

                  // Bouton de sélection
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ElevatedButton.icon(
                      onPressed: () {
                        // Logique à ajouter lorsque l'utilisateur clique sur le bouton
                        // Par exemple : Navigator.push(...) vers une autre page
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Modèle sélectionné !')),
                        );
                      },
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Sélectionner ce modèle'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        textStyle: const TextStyle(fontSize: 18),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}