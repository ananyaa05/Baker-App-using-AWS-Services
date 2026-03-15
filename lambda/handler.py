import json
import boto3
import os
import urllib.parse

# ── Try importing pymysql (installed on EC2, may not be in Lambda layer) ──
try:
    import pymysql
    RDS_AVAILABLE = True
except ImportError:
    RDS_AVAILABLE = False
    print("⚠️  pymysql not available — RDS logging disabled")

# ── AWS Clients ──────────────────────────────────────────────────────────────
rekognition = boto3.client('rekognition', region_name='us-east-1')
sns         = boto3.client('sns',         region_name='us-east-1')
s3          = boto3.client('s3',          region_name='us-east-1')

# ── Config from Environment Variables ────────────────────────────────────────
SNS_TOPIC_ARN      = os.environ.get('SNS_TOPIC_ARN', '')
BUCKET_NAME        = os.environ.get('BUCKET_NAME', '')
DB_HOST            = os.environ.get('DB_HOST', '')
DB_NAME            = os.environ.get('DB_NAME', 'bakerapp')
DB_USER            = os.environ.get('DB_USER', 'bakerapp')
DB_PASS            = os.environ.get('DB_PASS', '')
CONFIDENCE_MIN     = 80

# ── Recipe Database ───────────────────────────────────────────────────────────
RECIPES = {
    "Cake": {
        "name": "Classic Vanilla Sponge Cake",
        "ingredients": ["2 cups flour", "1.5 cups sugar", "3 eggs", "1 cup butter", "1 cup milk", "2 tsp vanilla", "2 tsp baking powder"],
        "steps": ["Preheat oven to 180C", "Cream butter and sugar until fluffy", "Beat in eggs one at a time", "Fold in flour and milk alternately", "Pour into greased pan", "Bake 30-35 mins until golden"]
    },
    "Chocolate Cake": {
        "name": "Rich Chocolate Fudge Cake",
        "ingredients": ["2 cups flour", "2 cups sugar", "3/4 cup cocoa powder", "2 eggs", "1 cup buttermilk", "1 cup hot coffee", "1/2 cup oil"],
        "steps": ["Preheat oven to 175C", "Mix all dry ingredients", "Whisk wet ingredients separately", "Combine wet and dry — do not overmix", "Bake in two 9-inch pans 30-35 mins", "Cool completely before frosting"]
    },
    "Croissant": {
        "name": "Buttery French Croissants",
        "ingredients": ["500g bread flour", "10g salt", "80g sugar", "10g instant yeast", "300ml cold milk", "280g cold butter for laminating"],
        "steps": ["Make dough and refrigerate overnight", "Laminate with butter — 3 folds of 3", "Shape into crescents", "Proof 2 hours at room temp", "Brush with egg wash", "Bake at 200C for 15-18 mins until deep golden"]
    },
    "Muffin": {
        "name": "Blueberry Buttermilk Muffins",
        "ingredients": ["2 cups flour", "3/4 cup sugar", "2 tsp baking powder", "1/2 tsp salt", "1 egg", "1 cup buttermilk", "1/3 cup melted butter", "1.5 cups blueberries"],
        "steps": ["Preheat oven to 190C", "Mix dry ingredients in large bowl", "Whisk wet ingredients separately", "Fold wet into dry until just combined", "Gently fold in blueberries", "Fill muffin cups 3/4 full", "Bake 20-25 mins"]
    },
    "Cookie": {
        "name": "Classic Chocolate Chip Cookies",
        "ingredients": ["2.25 cups flour", "1 tsp baking soda", "1 cup butter softened", "3/4 cup sugar", "3/4 cup brown sugar", "2 eggs", "2 tsp vanilla", "2 cups chocolate chips"],
        "steps": ["Preheat oven to 190C", "Cream butter and sugars", "Beat in eggs and vanilla", "Mix in flour mixture", "Stir in chocolate chips", "Drop by spoonfuls on sheet", "Bake 9-11 mins until golden"]
    },
    "Bread": {
        "name": "Simple Homemade White Bread",
        "ingredients": ["3 cups bread flour", "1 tsp salt", "2 tsp instant yeast", "1 tsp sugar", "1 cup warm water", "2 tbsp olive oil"],
        "steps": ["Combine dry ingredients", "Add water and oil mix to dough", "Knead 10 mins until smooth", "Rise 1 hour until doubled", "Shape and place in loaf tin", "Rise 45 more mins", "Bake at 200C for 30 mins"]
    },
    "Pastry": {
        "name": "Shortcrust Pastry Tart",
        "ingredients": ["250g plain flour", "125g cold butter cubed", "1 egg yolk", "3 tbsp cold water", "Pinch of salt"],
        "steps": ["Rub butter into flour until breadcrumb-like", "Add egg yolk and water bring together", "Wrap and chill 30 mins", "Roll out and line tart tin", "Blind bake at 180C for 15 mins", "Add filling and bake as needed"]
    },
    "Donut": {
        "name": "Glazed Yeast Doughnuts",
        "ingredients": ["3 cups flour", "7g instant yeast", "1/4 cup sugar", "3/4 cup warm milk", "2 eggs", "3 tbsp butter", "Oil for frying", "2 cups powdered sugar for glaze"],
        "steps": ["Make dough and knead 8 mins", "Rise 1 hour until doubled", "Roll out 1/2 inch cut rounds", "Rise 30 more mins", "Fry at 175C 1 min per side", "Drain and dip in glaze while warm"]
    },
    "Pie": {
        "name": "Classic Apple Pie",
        "ingredients": ["Pastry for double crust", "6 apples peeled sliced", "3/4 cup sugar", "2 tbsp flour", "1 tsp cinnamon", "1/4 tsp nutmeg", "1 tbsp butter"],
        "steps": ["Preheat oven to 220C", "Line pie dish with bottom crust", "Toss apples with sugar flour spices", "Fill crust dot with butter", "Cover with top crust seal edges", "Cut vents and brush with egg wash", "Bake 40-50 mins until golden"]
    },
    "Torte": {
        "name": "Sachertorte Austrian Chocolate Torte",
        "ingredients": ["150g dark chocolate", "150g butter", "6 eggs separated", "150g sugar", "150g flour", "Apricot jam", "Dark chocolate glaze"],
        "steps": ["Melt chocolate and butter", "Beat yolks with sugar until pale", "Fold in chocolate and flour", "Whisk egg whites fold in", "Bake at 175C for 45-50 mins", "Fill with apricot jam", "Coat with chocolate glaze"]
    },
    "Default": {
        "name": "All-Purpose Baked Treat",
        "ingredients": ["2 cups flour", "1 cup sugar", "1/2 cup butter", "2 eggs", "1 tsp vanilla", "1 tsp baking powder", "1/2 cup milk"],
        "steps": ["Preheat oven to 180C", "Cream butter and sugar", "Mix in eggs and vanilla", "Fold in flour baking powder and milk", "Pour into prepared pan", "Bake until golden and skewer comes clean"]
    },
    "Brownie": {
       "name": "Fudgy Chocolate Brownies",
       "ingredients": ["200g dark chocolate", "150g butter", "2 eggs", "1 cup sugar", "1 cup flour"],
       "steps": ["Melt chocolate and butter", "Whisk in eggs and sugar", "Fold in flour", "Bake at 180C for 25 mins"]
    },
    "Cupcake": {
       "name": "Vanilla Cupcakes",
       "ingredients": ["1.5 cups flour", "1 cup sugar", "2 eggs", "1/2 cup butter", "1/2 cup milk"],
       "steps": ["Cream butter and sugar", "Beat in eggs", "Fold in flour and milk", "Bake at 175C for 20 mins"]
},
}

BURNT_KEYWORDS = ["burnt", "burned", "charred", "overcooked", "fire", "smoke"]
PRIORITY_ORDER = ["Chocolate Cake", "Croissant", "Muffin", "Cookie", "Donut",
                  "Pie", "Torte", "Bread", "Pastry", "Cake","Brownie","Cupcake"]


def get_recipe(labels):
    label_names = [l['Name'] for l in labels if l['Confidence'] >= CONFIDENCE_MIN]
    for item in PRIORITY_ORDER:
        if item in label_names:
            return RECIPES[item], item
    return RECIPES["Default"], "Baked Good"


def is_burnt(labels):
    for label in labels:
        if any(k in label['Name'].lower() for k in BURNT_KEYWORDS):
            if label['Confidence'] >= 70:
                return True
    return False


def send_burnt_alert(bucket, key, labels):
    if not SNS_TOPIC_ARN:
        print("SNS_TOPIC_ARN not set — skipping")
        return
    burnt_labels = [l['Name'] for l in labels if any(k in l['Name'].lower() for k in BURNT_KEYWORDS)]
    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Message=f"BURNT ITEM DETECTED!\nFile: {key}\nBucket: {bucket}\nLabels: {', '.join(burnt_labels)}\nCheck your oven!",
        Subject="Baker App Alert: Burnt Item Detected"
    )
    print(f"SNS alert sent for: {key}")


def save_to_rds(result):
    """Save detection result to RDS MySQL database."""
    if not RDS_AVAILABLE or not DB_HOST or DB_HOST == 'pending':
        print("RDS not configured — skipping DB save")
        return

    try:
        conn = pymysql.connect(
            host=DB_HOST, user=DB_USER, password=DB_PASS,
            database=DB_NAME, connect_timeout=5
        )
        with conn.cursor() as cursor:
            # Create table if not exists
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS detections (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    image_key VARCHAR(500),
                    detected_as VARCHAR(100),
                    confidence FLOAT,
                    is_burnt BOOLEAN,
                    recipe_name VARCHAR(200),
                    all_labels TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            # Insert result
            cursor.execute("""
                INSERT INTO detections
                  (image_key, detected_as, confidence, is_burnt, recipe_name, all_labels)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, (
                result['image'],
                result['detected_as'],
                result['confidence'],
                result['is_burnt'],
                result['recipe']['name'],
                json.dumps(result['all_labels'])
            ))
        conn.commit()
        conn.close()
        print(f"Saved to RDS: {result['detected_as']}")
    except Exception as e:
        print(f"RDS save failed (non-critical): {e}")


def lambda_handler(event, context):
    print(f"Event: {json.dumps(event)}")
    results = []

    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key    = urllib.parse.unquote_plus(record['s3']['object']['key'])
        print(f"Processing: s3://{bucket}/{key}")

        try:
            # ── Rekognition ────────────────────────────────────────────
            response = rekognition.detect_labels(
                Image={'S3Object': {'Bucket': bucket, 'Name': key}},
                MaxLabels=15,
                MinConfidence=CONFIDENCE_MIN
            )
            labels = response['Labels']
            print(f"Labels: {[l['Name'] for l in labels]}")

            # ── Match recipe ──────────────────────────────────────────
            recipe, matched = get_recipe(labels)

            # ── Burnt check ───────────────────────────────────────────
            burnt = is_burnt(labels)
            if burnt:
                send_burnt_alert(bucket, key, labels)

            # ── Build result ──────────────────────────────────────────
            result = {
                "image": key,
                "detected_as": matched,
                "confidence": round(next(
                    (l['Confidence'] for l in labels if l['Name'] == matched), 0
                ), 1),
                "all_labels": [
                    {"name": l['Name'], "confidence": round(l['Confidence'], 1)}
                    for l in labels[:8]
                ],
                "is_burnt": burnt,
                "recipe": recipe
            }

            # ── Save to RDS ───────────────────────────────────────────
            save_to_rds(result)

            # ── Save result JSON to S3 ────────────────────────────────
            result_key = key.replace('uploads/', 'results/').rsplit('.', 1)[0] + '_result.json'
            s3.put_object(
                Bucket=bucket,
                Key=result_key,
                Body=json.dumps(result, indent=2),
                ContentType='application/json'
            )

            results.append(result)
            print(f"Done: {matched} | burnt={burnt}")

        except Exception as e:
            print(f"Error processing {key}: {e}")
            results.append({"image": key, "error": str(e)})

    return {
        "statusCode": 200,
        "headers": {"Access-Control-Allow-Origin": "*", "Content-Type": "application/json"},
        "body": json.dumps(results[0] if len(results) == 1 else results)
    }
