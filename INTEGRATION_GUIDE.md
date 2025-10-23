# NestJS Integration Guide

## Step-by-Step Integration with Your Sellr Backend

### 1. Install MeiliSearch Client

```bash
cd Backend
npm install meilisearch
```

### 2. Add Environment Variables

Add to `Backend/.env`:

```env
# MeiliSearch Configuration
MEILI_HOST=http://localhost:7700
MEILI_ADMIN_KEY=your_admin_key_from_api-keys.txt
```

### 3. Create MeiliSearch Module

**File: `Backend/src/meilisearch/meilisearch.module.ts`**

```typescript
import { Module } from "@nestjs/common";
import { MeiliSearchService } from "./meilisearch.service";

@Module({
  providers: [MeiliSearchService],
  exports: [MeiliSearchService],
})
export class MeiliSearchModule {}
```

### 4. Create MeiliSearch Service

Copy the example service:

```bash
# Copy from examples folder
cp ../meilisearch/examples/meilisearch.service.example.ts ./src/meilisearch/meilisearch.service.ts
```

### 5. Update App Module

**File: `Backend/src/app.module.ts`**

```typescript
import { MeiliSearchModule } from "./meilisearch/meilisearch.module";

@Module({
  imports: [
    // ... other modules
    MeiliSearchModule,
  ],
  // ...
})
export class AppModule {}
```

### 6. Update Product Module

**File: `Backend/src/product/product.module.ts`**

```typescript
import { MeiliSearchModule } from "../meilisearch/meilisearch.module";

@Module({
  imports: [
    // ... other imports
    MeiliSearchModule,
  ],
  // ...
})
export class ProductModule {}
```

### 7. Integrate with Product Service

Modify your existing product service to automatically sync with MeiliSearch:

```typescript
import { MeiliSearchService } from "../meilisearch/meilisearch.service";

@Injectable()
export class ProductService {
  constructor(
    private prisma: PrismaService,
    private meiliSearch: MeiliSearchService // Add this
  ) {}

  async create(
    createProductDto: any,
    userId: number,
    files: Express.Multer.File[]
  ) {
    // Your existing product creation logic
    const product = await this.prisma.product.create({
      data: {
        ...createProductDto,
        userId,
        images: uploadedImageUrls, // from your Cloudinary upload
      },
    });

    // ✨ NEW: Index in MeiliSearch
    this.meiliSearch
      .indexProduct({
        id: product.id,
        title: product.title,
        description: product.description,
        originalPrice: Number(product.originalPrice),
        discountedPrice: product.discountedPrice
          ? Number(product.discountedPrice)
          : undefined,
        discount: product.discount,
        category: product.category,
        condition: product.condition,
        tags: Array.isArray(product.tags) ? product.tags : [],
        userId: product.userId,
        stock: product.stock,
        images: product.images,
        createdAt: product.createdAt.toISOString(),
        updatedAt: product.updatedAt.toISOString(),
      })
      .catch((err) => {
        this.logger.error("Failed to index product in MeiliSearch:", err);
        // Don't fail the request if search indexing fails
      });

    return product;
  }

  async update(id: number, updateDto: any, userId: number) {
    const product = await this.prisma.product.update({
      where: { id, userId },
      data: updateDto,
    });

    // ✨ NEW: Update in MeiliSearch
    this.meiliSearch
      .updateProduct({
        id: product.id,
        ...updateDto,
        updatedAt: product.updatedAt.toISOString(),
      })
      .catch((err) => {
        this.logger.error("Failed to update product in MeiliSearch:", err);
      });

    return product;
  }

  async remove(id: number, userId: number) {
    const product = await this.prisma.product.delete({
      where: { id, userId },
    });

    // ✨ NEW: Delete from MeiliSearch
    this.meiliSearch.deleteProduct(id).catch((err) => {
      this.logger.error("Failed to delete product from MeiliSearch:", err);
    });

    return product;
  }
}
```

### 8. Add Search Endpoint

**File: `Backend/src/product/product.controller.ts`**

```typescript
@Get('search')
async search(
  @Query('q') query: string,
  @Query('category') category?: string,
  @Query('condition') condition?: string,
  @Query('minPrice') minPrice?: string,
  @Query('maxPrice') maxPrice?: string,
) {
  return this.productService.search(query, {
    category,
    condition,
    minPrice: minPrice ? parseFloat(minPrice) : undefined,
    maxPrice: maxPrice ? parseFloat(maxPrice) : undefined,
  });
}

@Post('sync-search')
@UseGuards(JwtAuthGuard) // Only admin should access this
async syncSearch() {
  return this.productService.syncAllToSearch();
}
```

**File: `Backend/src/product/product.service.ts`**

```typescript
async search(query: string, filters?: {
  category?: string;
  condition?: string;
  minPrice?: number;
  maxPrice?: number;
}) {
  const filterArray: string[] = [];

  if (filters?.category) {
    filterArray.push(`category = "${filters.category}"`);
  }

  if (filters?.condition) {
    filterArray.push(`condition = "${filters.condition}"`);
  }

  if (filters?.minPrice !== undefined) {
    filterArray.push(`originalPrice >= ${filters.minPrice}`);
  }

  if (filters?.maxPrice !== undefined) {
    filterArray.push(`originalPrice <= ${filters.maxPrice}`);
  }

  return await this.meiliSearch.search(query, {
    filter: filterArray.length > 0 ? filterArray : undefined,
    sort: ['discount:desc'],
    limit: 20,
  });
}

async syncAllToSearch() {
  const products = await this.prisma.product.findMany();

  const documents = products.map(product => ({
    id: product.id,
    title: product.title,
    description: product.description,
    originalPrice: Number(product.originalPrice),
    discountedPrice: product.discountedPrice ? Number(product.discountedPrice) : undefined,
    discount: product.discount,
    category: product.category,
    condition: product.condition,
    tags: Array.isArray(product.tags) ? product.tags : [],
    userId: product.userId,
    stock: product.stock,
    images: product.images,
    createdAt: product.createdAt.toISOString(),
    updatedAt: product.updatedAt.toISOString(),
  }));

  await this.meiliSearch.syncAllProducts(documents);

  return { message: `Synced ${documents.length} products` };
}
```

### 9. Initial Sync

After deployment, run this ONCE to sync existing products:

```bash
# Using curl
curl -X POST http://localhost:3000/api/products/sync-search \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"

# Or use Postman
POST http://localhost:3000/api/products/sync-search
Headers: Authorization: Bearer YOUR_JWT_TOKEN
```

### 10. Test the Search

```bash
# Search for "laptop"
curl "http://localhost:3000/api/products/search?q=laptop"

# Search with filters
curl "http://localhost:3000/api/products/search?q=phone&category=electronics&maxPrice=1000"
```

---

## Frontend Integration (Next.js)

### Option 1: Search via Backend API (Recommended)

**File: `frontend/src/services/productService.ts`**

```typescript
export async function searchProducts(
  query: string,
  filters?: {
    category?: string;
    condition?: string;
    minPrice?: number;
    maxPrice?: number;
  }
) {
  const params = new URLSearchParams({ q: query });

  if (filters?.category) params.append("category", filters.category);
  if (filters?.condition) params.append("condition", filters.condition);
  if (filters?.minPrice) params.append("minPrice", filters.minPrice.toString());
  if (filters?.maxPrice) params.append("maxPrice", filters.maxPrice.toString());

  const response = await fetch(`/api/products/search?${params}`, {
    credentials: "include",
  });

  if (!response.ok) {
    throw new Error("Search failed");
  }

  return response.json();
}
```

### Option 2: Direct Search from Browser (Public Search Only)

**File: `frontend/.env.local`**

```env
NEXT_PUBLIC_MEILI_HOST=http://localhost:7700
NEXT_PUBLIC_MEILI_SEARCH_KEY=your_search_key
```

**File: `frontend/src/services/searchService.ts`**

```typescript
export async function directSearch(query: string) {
  const response = await fetch(
    `${process.env.NEXT_PUBLIC_MEILI_HOST}/indexes/products/search`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Meili-API-Key": process.env.NEXT_PUBLIC_MEILI_SEARCH_KEY!,
      },
      body: JSON.stringify({
        q: query,
        limit: 20,
      }),
    }
  );

  return response.json();
}
```

---

## Troubleshooting

### Products Not Appearing in Search

1. Check if MeiliSearch is running:

   ```bash
   curl http://localhost:7700/health
   ```

2. Check if products are indexed:

   ```bash
   curl "http://localhost:7700/indexes/products/stats" \
     -H "X-Meili-API-Key: YOUR_ADMIN_KEY"
   ```

3. Run manual sync:
   ```bash
   curl -X POST http://localhost:3000/api/products/sync-search \
     -H "Authorization: Bearer YOUR_JWT"
   ```

### Search Returns Empty Results

1. Verify searchable attributes are configured
2. Check if documents exist in index
3. Try a broader search query

### Connection Refused

1. Ensure MeiliSearch container is running: `docker ps`
2. Check MEILI_HOST is correct in .env
3. Verify API key is valid

---

## Performance Tips

1. **Batch Index Updates**: When creating multiple products, batch them
2. **Async Indexing**: Don't wait for MeiliSearch responses (use catch)
3. **Pagination**: Use limit/offset for large result sets
4. **Caching**: Cache frequent searches in Redis
5. **Monitoring**: Monitor MeiliSearch performance via `/stats` endpoint

---

## Next Steps

1. ✅ Complete the integration
2. ✅ Run initial sync
3. ✅ Test search functionality
4. ✅ Set up automated backups
5. ✅ Deploy to production with HTTPS
6. ✅ Monitor and optimize search queries
