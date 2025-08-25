# QBX Animal Farming v1

An advanced animal farming system for QBX Framework with enhanced features and realistic animal management.

## Features

- **🐄 Multi-Animal Support**: Cows, Pigs, and Chickens
- **🏡 Farmlot Ownership**: Buy and manage multiple farm lots
- **📊 Advanced Stats System**: Health, Hunger, and Thirst tracking
- **🥛 Product Collection**: Realistic cooldowns and quality system
- **🔪 Butchering System**: Skill-based yields with minigames
- **🚰 Water Trough System**: Automated hydration for animals
- **💰 Economic Integration**: Full ox_inventory and money system integration
- **🎯 Target System**: ox_target integration for all interactions
- **📱 Modern UI**: ox_lib menus and notifications

## Installation

1. **Database Setup**:
   ```sql
   -- Run the provided animal_farming.sql file
   ```

2. **Dependencies**:
   - qbx_core
   - ox_lib
   - ox_inventory
   - ox_target
   - oxmysql

3. **Resource Setup**:
   - Place `qbx_animalfarmingv1` in your resources folder
   - Add `ensure qbx_animalfarmingv1` to your server.cfg
   - Configure the settings in `shared/config.lua`

## Configuration

### Basic Settings
```lua
Config.Debug = false -- Enable debug logging
Config.MaxFarmlotsPerPlayer = false -- false = unlimited
```

### Animal Configuration
Each animal type has its own configuration:
- **Price**: Purchase cost
- **Stats**: Base health, hunger, thirst
- **Products**: What they produce and cooldowns
- **Behavior**: Wandering distance and AI settings

### Economic Settings
- **Feed Cost**: Configure animal feed prices
- **Product Values**: Set market values for products
- **Lot Prices**: Farmlot purchase costs

## Usage

### For Players

1. **Buy a Farmlot**:
   - Visit the Farmlot Manager NPC
   - Select lot type (cow, pig, chicken)
   - Pay the required amount

2. **Purchase Animals**:
   - Visit the Animal Vendor NPC
   - Choose animal type
   - Select which lot to place them on

3. **Animal Care**:
   - Feed animals regularly with animal feed
   - Ensure water troughs are filled
   - Monitor health, hunger, and thirst levels

4. **Collect Products**:
   - Milk from female cows (every 3 days)
   - Eggs from chickens (every 30 minutes)
   - Pork from pigs (every 2 hours)

5. **Butchering**:
   - Dead animals can be butchered for meat
   - Requires a knife and skill minigame
   - Higher skill = better yields

### For Admins

Available commands:
- `/af_list` - List your animals
- `/af_stats` - Check animal statistics

## API

### Server Events
```lua
-- Buy farmlot
TriggerServerEvent('animal_farming:server:buyFarmlot', data)

-- Buy animal
TriggerServerEvent('animal_farming:server:buyAnimal', data)

-- Feed animal
TriggerServerEvent('animal_farming:server:feedAnimal', animalId)

-- Collect product
TriggerServerEvent('animal_farming:server:collectProduct', animalId)
```

### Client Events
```lua
-- Spawn animal
TriggerClientEvent('animal_farming:client:spawnAnimal', src, data)

-- Update stats
TriggerClientEvent('animal_farming:client:updateStats', src, animalId, stats)

-- Despawn animal
TriggerClientEvent('animal_farming:client:despawnAnimal', src, animalId)
```

## Database Schema

The system uses 7 main tables:
- `animal_farmlots` - Player-owned farm lots
- `animal_livestock` - Individual animals
- `animal_water_troughs` - Water systems
- `animal_transactions` - Economic tracking
- `animal_production_log` - Product collection history
- `animal_death_log` - Animal death records
- `animal_activity_log` - General activity tracking

## Troubleshooting

### Common Issues

1. **Animals not spawning**:
   - Check server console for errors
   - Verify database tables exist
   - Ensure all dependencies are loaded

2. **Syntax errors**:
   - The original error was fixed - missing `end` statements
   - Ensure proper Lua syntax in config files

3. **Performance issues**:
   - Adjust `Config.StatDecay` intervals
   - Limit animals per lot
   - Monitor server performance

### Debug Mode
Enable `Config.Debug = true` for detailed console logging.

## Support

For issues and support:
1. Check the console for error messages
2. Verify all dependencies are up to date
3. Review the configuration settings
4. Check database table structure

## Changelog

### v1.0.0
- Initial release
- Multi-animal support
- Advanced stats system
- Economic integration
- Quality-based production
- Skill-based butchering

## License

This resource is provided as-is for educational and development purposes.

---

**Note**: This system requires proper server configuration and may need adjustments based on your specific server setup and requirements.