# AudioScape Boombox API Documentation

## Overview

This document provides detailed information about the AudioScape API endpoints for developers integrating with the AudioScape music service. The API allows for music discovery, user preferences management, and telemetry tracking.

## Authentication

All API endpoints require authentication using an API key that should be included in the request headers.

**Required Headers:**

- `X-API-Key`: Your AudioScape API key
- For certain endpoints: `X-AS-Key`: AudioScape system key (for administrative operations)

## Base URL

```
https://api.audioscape.ai/boombox/
```

## Endpoints

### Settings Management

#### Update Settings

Updates game-specific settings for the BoomBox player.

```
POST /settings
```

**Headers:**

- `X-API-Key`: Required
- `X-AS-Key`: Required (administrative key, internal use only not for public use)

**Request Body:**

```json
{
  "game_id": 123456,
  "settings": {
    "position": {
      "x": 1,
      "y": 0.5
    },
    "volume": 0.5,
    "accentColour": "#FFFFFF"
  }
}
```

**Response:**

```json
{
  "message": "Settings for game '123456' updated successfully"
}
```

**Status Codes:**

- `200`: Success
- `400`: Missing required parameters
- `403`: Unauthorized (invalid X-AS-Key)
- `500`: Server error

#### Get Settings

Retrieves game-specific settings for the BoomBox player.

```
GET /settings?game_id=123456
```

**Headers:**

- `X-API-Key`: Required

**Query Parameters:**

- `game_id`: Required - The game identifier

**Response:**

```json
{
  "game_id": 123456,
  "settings": {
    "position": {
      "x": 1,
      "y": 0.5
    },
    "volume": 0.5,
    "accentColour": "#FFFFFF"
  }
}
```

**Status Codes:**

- `200`: Success (returns default settings if none found)
- `400`: Missing required parameters
- `500`: Server error

### Music Discovery

#### Get Genres

Retrieves available music genres or custom stations.

```
GET /genres?game_id=123456&include_metadata=true
```

**Headers:**

- `X-API-Key`: Required

**Query Parameters:**
I'll create a new API endpoint to retrieve the additional music data (num_bars, beat_grid, and song_sections) following the existing patterns for validation, error handling, and caching.

Here's the implementation:

```javascript
module.exports.getMusicData = async (event) => {
  const pool = new Pool({
    host: process.env.DB_HOST,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    port: Number(process.env.DB_PORT ?? 5432),
    database: 'postgres',
    max: 50,
    idleTimeoutMillis: 5000,
    connectionTimeoutMillis: 2000,
  })

  const requestData = JSON.parse(event.body)
  const { asset_id, asset_ids, game_id, game_name } = requestData
  const api_key = event.headers['X-API-Key']

  // Input validation
  if ((!asset_id && !asset_ids) || !api_key || !game_id || !game_name) {
    return {
      statusCode: 400,
      body: JSON.stringify({
        error:
          'Either asset_id or asset_ids, plus game_id, game_name, and api_key are required',
      }),
    }
  }

  // Determine if we're looking up a single asset or multiple
  let lookupIds = []
  if (asset_id) {
    lookupIds = [asset_id]
  } else if (Array.isArray(asset_ids) && asset_ids.length > 0) {
    lookupIds = asset_ids
  } else {
    return {
      statusCode: 400,
      body: JSON.stringify({
        error: 'Invalid asset_id or asset_ids parameter',
      }),
    }
  }

  // Generate cache key
  const cacheKey = `music_data_${lookupIds.sort().join('_')}`

  // Try to get from cache first
  const cachedData = await getFromCache(cacheKey)
  if (cachedData) {
    return {
      statusCode: 200,
      headers: {
        'Cache-Control': 'public, max-age=3600',
        'X-AS-Cache': 'HIT',
        'X-AS-Cache-Key': cacheKey,
      },
      body: JSON.stringify(cachedData),
    }
  }

  const lookup = lookupIds.join(',')

  const query = `
    SELECT
      asset_id,
      num_bars,
      beat_grid,
      song_sections
    FROM music
    WHERE asset_id IN (${lookup})
  `

  try {
    const data = await sendQueryAsync(pool, query)

    // Cache the results
    await setCache(cacheKey, data, {
      asset_ids: lookupIds,
      api_key: api_key,
      timestamp: new Date().toISOString(),
      cacheVersion: '1.0',
    })

    return {
      statusCode: 200,
      headers: {
        'Cache-Control': 'public, max-age=3600',
        'X-AS-Cache': 'MISS',
        'X-AS-Cache-Key': cacheKey,
      },
      body: JSON.stringify(data),
    }
  } catch (error) {
    console.error(error)
    return {
      statusCode: 500,
      body: JSON.stringify({ error: 'Could not retrieve music data' }),
    }
  } finally {
    await pool.end()
  }
}
```

This endpoint follows the existing patterns from the codebase:

1. **Input Validation**: Checks for required parameters (asset_id or asset_ids, game_id, game_name, and api_key)
2. **Caching**: Uses the existing cache functions (getFromCache and setCache)
3. **Database Connection**: Uses the Pool connection pattern seen in other endpoints
4. **Query Execution**: Uses the sendQueryAsync helper function
5. **Response Format**: Follows the standard response format with proper headers and status codes
6. **Error Handling**: Includes try/catch blocks and appropriate error responses

The endpoint supports both single asset_id lookup and batch lookups via the asset_ids array parameter, similar to how other endpoints handle this pattern. The cache key is generated based on the sorted asset IDs to ensure consistent caching regardless of the order of IDs in the request.

- `game_id`: Optional - Game identifier for game-specific stations
- `include_metadata`: Optional - Set to "true" to include station metadata

**Response (with metadata):**

```json
{
  "stations": [
    {
      "name": "Pop",
      "metadata": {
        "description": "Popular music hits",
        "icon": "pop_icon.png"
      }
    },
    {
      "name": "Rock",
      "metadata": {
        "description": "Rock music classics",
        "icon": "rock_icon.png"
      }
    }
  ]
}
```

**Response (without metadata):**

```json
["Pop", "Rock", "Hip-hop", "EDM"]
```

**Status Codes:**

- `200`: Success
- `500`: Server error

#### Get Emotions

Retrieves available emotion filters for music.

```
GET /emotions
```

**Response:**

```json
["Dance", "Exciting", "Angry", "Chill", "Happy", "Scary", "Sad", "Laid Back"]
```

**Status Codes:**

- `200`: Success

#### Search Songs

Searches for songs based on genre, emotion, or text query.

```
POST /search
```

**Headers:**

- `X-API-Key`: Required

**Request Body:**

```json
{
  "game_id": 123456,
  "game_name": "My Game",
  "genre": "Pop",
  "emotion": "Happy",
  "limit": 25
}
```

OR

```json
{
  "game_id": 123456,
  "game_name": "My Game",
  "query": "summer beach",
  "limit": 25
}
```

**Response:**

```json
[
  {
    "asset_id": "12345",
    "asset_name": "Summer Vibes",
    "asset_audio_details_music_album": "Summer Collection",
    "asset_audio_details_music_genre": "Pop",
    "asset_bpm": 120,
    "asset_first_beat_offset": 0.5,
    "asset_first_downbeat": 1.2
  }
]
```

**Status Codes:**

- `200`: Success
- `400`: Missing required parameters or invalid limit
- `500`: Server error

**Response Headers:**

- `Cache-Control`: Caching directives
- `X-AS-Cache`: Cache status (HIT/MISS)
- `X-AS-Cache-Key`: Cache key used

#### Get Music Data

Retrieves additional music data including number of bars, beat grid, and song sections for specific songs.

```
POST /assets/data
```

**Headers:**

- `X-API-Key`: Required

**Request Body:**

Either provide a single asset_id:

```json
{
  "asset_id": "12345",
  "game_id": 123456,
  "game_name": "My Game"
}
```

Or provide multiple asset_ids:

```json
{
  "asset_ids": [9047044521, 9046443555],
  "game_id": 1234,
  "game_name": "Test Filipe"
}
```

**Response:**

```json
[
  {
    "asset_id": "9046443555",
    "num_bars": 49,
    "beat_grid": {
      "beat_nums": [
        1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4,
        1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4,
        1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4,
        1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4,
        1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4,
        1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4,
        1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4,
        1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4,
        1, 2, 3, 4, 1
      ],
      "beat_times": [
        0.00971882099999958, 0.6366575959999985, 1.240376417000003,
        1.8673151929999934, 2.482643990999991, 3.1095827659999906,
        3.713301587000004, 4.340240363000001, 4.955569161000001,
        5.582507937000002, 6.186226757000002, 6.813165533000001,
        7.428494330999981, 8.055433107000031, 8.670761905000031,
        9.29770068000003, 9.901419501000031, 10.52835827700003,
        11.143687075000031, 11.77062585000003, 12.374344671000031,
        13.012893424000032, 13.61661224500003, 14.24355102000003,
        14.847269841000031, 15.485818594000081, 16.089537415000073,
        16.716476190000073, 17.331804989000073, 17.958743764000072,
        18.562462585000073, 19.189401361000073, 19.804730159000073,
        20.431668934000072, 21.035387755000073, 21.662326531000073,
        22.277655329000073, 22.904594104000072, 23.508312925000073,
        24.135251701000072, 24.750580499000073, 25.377519274000072,
        25.981238095000073, 26.608176871000072, 27.223505669000073,
        27.850444444000072, 28.454163265000073, 29.092712018000075,
        29.696430839000072, 30.32336961500007, 30.938698413000072,
        31.554027210999912, 32.169356008999785, 32.79629478499979,
        33.41162358299979, 34.03856235799979, 34.64228117899979,
        35.28082993199978, 35.884548752999784, 36.499877550999784,
        37.115206348999784, 37.753755101999786, 38.35747392299979,
        38.97280272099979, 39.58813151899979, 40.215070294999784,
        40.830399092999784, 41.45733786799978, 42.07266666699979,
        42.68799546499979, 43.30332426299979, 43.95348299299979,
        44.54559183699978, 45.17253061199978, 45.77624943299978,
        46.40318820899979, 47.01851700699979, 47.645455781999786,
        48.24917460299979, 48.87611337899978, 49.49144217699978,
        50.10677097499978, 50.72209977299978, 51.360648525999785,
        51.964367346999786, 52.57969614499979, 53.20663492099978,
        53.84518367299979, 54.43729251699978, 55.05262131499978,
        55.679560090999786, 56.306498865999785, 56.910217686999786,
        57.54876643999979, 58.15248526099978, 58.76781405899978,
        59.38314285699978, 60.010081632999785, 60.625410430999786,
        61.252349205999785, 61.856068026999786, 62.48300680299979,
        63.09833560099979, 63.74849433100023, 64.34060317500037,
        64.96754195000037, 65.57126077100037, 66.19819954600037,
        66.81352834500036, 67.44046712000036, 68.04418594100036,
        68.67112471700037, 69.28645351500036, 69.90178231300037,
        70.51711111100036, 71.14404988700036, 71.75937868500036,
        72.37470748300036, 73.00164625900037, 73.64019501100036,
        74.23230385500037, 74.84763265300036, 75.47457142900036,
        76.08990022700036, 76.70522902500036, 77.34377777800036,
        77.94749659900036, 78.56282539700037, 79.17815419500036,
        79.80509297100036, 80.42042176900036, 81.04736054400036,
        81.65107936500036, 82.28962811800037, 82.89334693900037,
        83.52028571400037, 84.12400453500037, 84.75094331100036,
        85.36627210900036, 85.99321088400036, 86.60853968300036,
        87.23547845800036, 87.83919727900036, 88.46613605400036,
        89.08146485300036, 89.69679365100036, 90.31212244900036,
        90.95067120200036, 91.55439002300037, 92.18132879800037,
        92.78504761900037, 93.42359637200036, 94.02731519300036,
        94.65425396800036, 95.26958276600035, 95.89652154200036,
        96.50024036300036, 97.12717913800036, 97.74250793700035,
        98.36944671200037, 98.97316553300035, 99.60010430800035,
        100.21543310700036, 100.84237188200036, 101.44609070300037,
        102.07302947800036, 102.68835827700036, 103.31529705200036,
        103.91901587300036, 104.54595464900036, 105.16128344700036,
        105.78822222200036, 106.39194104300036, 107.01887981900036,
        107.63420861700037, 108.26114739200037, 108.87647619000036,
        109.50341496600036, 110.10713378700036, 110.74568254000036,
        111.34940136100036, 111.97634013600036, 112.58005895700036,
        113.21860771000036, 113.82232653100036, 114.44926530600036,
        115.05298412700036, 115.69153288000037, 116.29525170100037,
        116.92219047600037, 117.53751927400036, 118.16445805000036,
        118.76817687100036, 119.38350566900036, 120.01044444400036,
        120.62577324300037, 121.24110204100036
      ]
    },
    "song_sections": null
  },
  {
    "asset_id": "9047044521",
    "num_bars": 58,
    "beat_grid": {
      "beat_nums": [
        1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4,
        1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4,
        1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4,
        1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4,
        1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4,
        1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4,
        1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4,
        1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4,
        1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4,
        1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4
      ],
      "beat_times": [
        0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5, 5.5, 6, 6.5, 7, 7.5, 8, 8.5,
        9, 9.5, 10, 10.5, 11, 11.5, 12, 12.5, 13, 13.5, 14, 14.5, 15, 15.5, 16,
        16.5, 17, 17.5, 18, 18.5, 19, 19.5, 20, 20.5, 21, 21.5, 22, 22.5, 23,
        23.5, 24, 24.5, 25, 25.5, 26, 26.5, 27, 27.5, 28, 28.5, 29, 29.5, 30,
        30.5, 31, 31.5, 32, 32.5, 33, 33.5, 34, 34.5, 35, 35.5, 36, 36.5, 37,
        37.5, 38, 38.5, 39, 39.5, 40, 40.5, 41, 41.5, 42, 42.5, 43, 43.5, 44,
        44.5, 45, 45.5, 46, 46.5, 47, 47.5, 48, 48.5, 49, 49.5, 50, 50.5, 51,
        51.5, 52, 52.5, 53, 53.5, 54, 54.5, 55, 55.5, 56, 56.5, 57, 57.5, 58,
        58.5, 59, 59.5, 60, 60.5, 61, 61.5, 62, 62.5, 63, 63.5, 64, 64.5, 65,
        65.5, 66, 66.5, 67, 67.5, 68, 68.5, 69, 69.5, 70, 70.5, 71, 71.5, 72,
        72.5, 73, 73.5, 74, 74.5, 75, 75.5, 76, 76.5, 77, 77.5, 78, 78.5, 79,
        79.5, 80, 80.5, 81, 81.5, 82, 82.5, 83, 83.5, 84, 84.5, 85, 85.5, 86,
        86.5, 87, 87.5, 88, 88.5, 89, 89.5, 90, 90.5, 91, 91.5, 92, 92.5, 93,
        93.5, 94, 94.5, 95, 95.5, 96, 96.5, 97, 97.5, 98, 98.5, 99, 99.5, 100,
        100.5, 101, 101.5, 102, 102.5, 103, 103.5, 104, 104.5, 105, 105.5, 106,
        106.5, 107, 107.5, 108, 108.5, 109, 109.5, 110, 110.5, 111, 111.5, 112,
        112.5, 113, 113.5, 114, 114.5, 115, 115.5
      ]
    },
    "song_sections": [
      {
        "name": "Test Section",
        "color": "rgba(0, 200, 200, 0.5)",
        "end_time": 30,
        "metadata": [
          {
            "key": "Key",
            "value": "Value"
          }
        ],
        "start_time": 0
      }
    ]
  }
]
```

**Status Codes:**

- `200`: Success
- `400`: Missing required parameters
- `500`: Server error

**Response Headers:**

- `Cache-Control`: Caching directives
- `X-AS-Cache`: Cache status (HIT/MISS)
- `X-AS-Cache-Key`: Cache key used

#### Get Songs by IDs

Retrieves detailed information for specific songs by their asset IDs.

```
POST /assets/details
```

**Headers:**

- `X-API-Key`: Required

**Request Body:**

```json
{
  "asset_ids": ["12345", "67890"],
  "game_id": 123456,
  "game_name": "My Game"
}
```

**Response:**

```json
[
  {
    "asset_id": "12345",
    "asset_description": "Upbeat summer song",
    "asset_name": "Summer Vibes",
    "asset_audio_details_music_album": "Summer Collection",
    "asset_audio_details_music_genre": "Pop",
    "asset_audio_details_tags": "Happy_music,Dance_music",
    "asset_bpm": 120,
    "asset_first_beat_offset": 0.5,
    "asset_first_downbeat": 1.2
  }
]
```

**Status Codes:**

- `200`: Success
- `400`: Missing required parameters
- `500`: Server error

### User Preferences

#### Like a Song

Marks a song as liked by a user.

```
POST /like
```

**Headers:**

- `X-API-Key`: Required

**Request Body:**

```json
{
  "user_id": 123456,
  "asset_id": "78901"
}
```

**Response:**

```json
{
  "message": "Asset '78901' liked by user '123456' successfully"
}
```

**Status Codes:**

- `200`: Success
- `400`: Missing required parameters
- `500`: Server error

#### Batch Like Songs

Marks multiple songs as liked by users in a single request.

```
POST /batchLike
```

**Headers:**

- `X-API-Key`: Required

**Request Body:**

```json
{
  "likes": [
    {
      "user_id": 123456,
      "asset_id": "78901"
    },
    {
      "user_id": 123456,
      "asset_id": "78902"
    }
  ]
}
```

**Response:**

```json
{
  "message": "Assets liked successfully"
}
```

**Status Codes:**

- `200`: Success
- `400`: Missing required parameters
- `500`: Server error

#### Unlike a Song

Removes a song from a user's liked songs.

```
POST /unlike
```

**Request Body:**

```json
{
  "user_id": 123456,
  "asset_id": "78901"
}
```

**Response:**

```json
{
  "message": "Asset '78901' unliked by user '123456' successfully"
}
```

**Status Codes:**

- `200`: Success
- `400`: Missing required parameters
- `500`: Server error

#### Batch Unlike Songs

Removes multiple songs from users' liked songs in a single request.

```
POST /batchUnlike
```

**Headers:**

- `X-API-Key`: Required

**Request Body:**

```json
{
  "unlikes": [
    {
      "user_id": 123456,
      "asset_id": "78901"
    },
    {
      "user_id": 123456,
      "asset_id": "78902"
    }
  ]
}
```

**Response:**

```json
{
  "message": "Assets unliked successfully"
}
```

**Status Codes:**

- `200`: Success
- `400`: Missing required parameters
- `500`: Server error

#### Get Liked Songs

Retrieves all songs liked by a specific user.

```
GET /likes?user_id=123456
```

**Headers:**

- `X-API-Key`: Required

**Query Parameters:**

- `user_id`: Required - The user identifier

**Response:**

```json
[
  {
    "asset_id": "12345",
    "asset_description": "Upbeat summer song",
    "asset_name": "Summer Vibes",
    "asset_audio_details_music_album": "Summer Collection",
    "asset_audio_details_music_genre": "Pop",
    "asset_audio_details_tags": "Happy_music,Dance_music",
    "asset_bpm": 120,
    "asset_first_beat_offset": 0.5,
    "asset_first_downbeat": 1.2,
    "liked_at": "2025-03-24T12:00:00.000Z"
  }
]
```

**Status Codes:**

- `200`: Success (returns empty array if no likes found)
- `400`: Missing required parameters
- `500`: Server error

#### Batch Get Liked Songs

Retrieves liked songs for multiple users in a single request.

```
POST /batchLikes
```

**Headers:**

- `X-API-Key`: Required

**Request Body:**

```json
{
  "user_ids": [123456, 789012]
}
```

**Response:**

```json
[
  {
    "user_id": 123456,
    "likes": [
      {
        "asset_id": "12345",
        "asset_name": "Summer Vibes",
        "asset_audio_details_music_album": "Summer Collection",
        "asset_audio_details_music_genre": "Pop",
        "asset_bpm": 120,
        "asset_first_beat_offset": 0.5,
        "asset_first_downbeat": 1.2,
        "liked_at": "2025-03-24T12:00:00.000Z"
      }
    ]
  },
  {
    "user_id": 789012,
    "likes": []
  }
]
```

**Status Codes:**

- `200`: Success
- `400`: Missing required parameters
- `500`: Server error

### Telemetry

#### Batch Telemetry

Records multiple telemetry events in a single request.

```
POST /batchTelemetry
```

**Headers:**

- `X-API-Key`: Required

**Request Body:**

```json
{
  "AS-BoomBox-ClientDeviceType": "mobile",
  "AS-BoomBox-GameId": 123456,
  "AS-BoomBox-GameName": "My Game",
  "payload": [
    {
      "event_type": "play",
      "user_id": 123456,
      "asset_id": "78901"
    },
    {
      "event_type": "skip",
      "user_id": 123456,
      "asset_id": "78902"
    }
  ]
}
```

**Response:**

```json
{
  "message": "Telemetry events recorded successfully"
}
```

**Status Codes:**

- `200`: Success
- `400`: Missing required parameters
- `500`: Server error

## Error Handling

All endpoints return appropriate HTTP status codes and error messages in the following format:

```json
{
  "error": "Error message describing the issue"
}
```

## Rate Limiting

API requests are subject to rate limiting. Exceeding the rate limit will result in HTTP 429 responses.

## Caching

The search endpoint implements caching with a TTL of 1 week. Cache status is indicated in response headers.

Here's the documentation entry for the new API endpoint that retrieves the music data (num_bars, beat_grid, and song_sections):
