import 'package:flutter/material.dart';
import '../services/air_quality_service.dart';

class AirQualityInfoSheet extends StatelessWidget {
  final AirQualityDataPoint data;
  
  const AirQualityInfoSheet({Key? key, required this.data}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top title bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Air Quality Index (AQI)',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const Divider(),
          
          // AQI value and rating
          Row(
            children: [
              _buildAqiIndicator(context),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getAqiDescription(data.aqi),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _getColorForAQI(data.aqi),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Current air quality ${data.aqi.round()}',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Pollutant information
          _buildDetailsCard(context),
          
          const SizedBox(height: 16),
          
          // Health advice
          _buildHealthAdvice(context),
          
          const SizedBox(height: 24),
          
          // Data source information
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Data source: ${data.source}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildAqiIndicator(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: _getColorForAQI(data.aqi).withOpacity(0.2),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          data.aqi.round().toString(),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: _getColorForAQI(data.aqi),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
  
  Widget _buildDetailsCard(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Main Pollutant Information',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _buildPollutantInfo(
              icon: Icons.coronavirus_outlined,
              title: 'Main pollutant',
              value: data.pollutant ?? 'No significant pollutant',
            ),
            const Divider(),
            _buildPollutantInfo(
              icon: Icons.location_on_outlined,
              title: 'Location',
              value: '${data.location.latitude.toStringAsFixed(5)}, ${data.location.longitude.toStringAsFixed(5)}',
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildPollutantInfo({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.grey)),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildHealthAdvice(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.health_and_safety, color: Colors.teal),
                const SizedBox(width: 8),
                Text(
                  'Health Advice',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_getHealthAdvice(data.aqi)),
          ],
        ),
      ),
    );
  }
  
  String _getAqiDescription(double aqi) {
    if (aqi <= 50) return 'Excellent';
    if (aqi <= 100) return 'Good';
    if (aqi <= 150) return 'Lightly Polluted';
    if (aqi <= 200) return 'Moderately Polluted';
    if (aqi <= 300) return 'Heavily Polluted';
    return 'Severely Polluted';
  }
  
  String _getHealthAdvice(double aqi) {
    if (aqi <= 50) {
      return 'Air quality is satisfactory, and air pollution poses little or no risk.';
    } else if (aqi <= 100) {
      return 'Air quality is acceptable; however, there may be a moderate health concern for a very small number of people who are unusually sensitive to air pollution.';
    } else if (aqi <= 150) {
      return 'Members of sensitive groups may experience health effects. The general public is not likely to be affected. Consider reducing outdoor activities.';
    } else if (aqi <= 200) {
      return 'Everyone may begin to experience health effects; members of sensitive groups may experience more serious health effects. Reduce outdoor activities.';
    } else if (aqi <= 300) {
      return 'Health warnings of emergency conditions. The entire population is more likely to be affected. Avoid outdoor activities.';
    } else {
      return 'Health alert: everyone may experience more serious health effects. Everyone should avoid outdoor activities.';
    }
  }
  
  Color _getColorForAQI(double aqi) {
    if (aqi <= 50) return Colors.green;
    if (aqi <= 100) return Colors.yellow[700]!;
    if (aqi <= 150) return Colors.orange;
    if (aqi <= 200) return Colors.red;
    if (aqi <= 300) return Colors.purple;
    return Colors.brown;
  }
} 