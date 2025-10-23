// Example NestJS MeiliSearch Service
// Place in: Backend/src/meilisearch/meilisearch.service.ts

import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { MeiliSearch, Index } from 'meilisearch';
import { ConfigService } from '@nestjs/config';

export interface ProductDocument {
  id: number;
  title: string;
  description: string;
  originalPrice: number;
  discountedPrice?: number;
  discount: number;
  category: string;
  condition: string;
  tags: string[];
  userId: number;
  stock: number;
  images: string[];
  createdAt: string;
  updatedAt: string;
}

@Injectable()
export class MeiliSearchService implements OnModuleInit {
  private readonly logger = new Logger(MeiliSearchService.name);
  private client: MeiliSearch;
  private productsIndex: Index<ProductDocument>;
  private readonly indexName = 'products';

  constructor(private configService: ConfigService) {
    const host = this.configService.get<string>('MEILI_HOST', 'http://localhost:7700');
    const apiKey = this.configService.get<string>('MEILI_ADMIN_KEY');

    if (!apiKey) {
      this.logger.warn('MEILI_ADMIN_KEY not set. Search functionality will be limited.');
    }

    this.client = new MeiliSearch({
      host,
      apiKey,
    });

    this.productsIndex = this.client.index<ProductDocument>(this.indexName);
  }

  async onModuleInit() {
    try {
      await this.initializeIndex();
      this.logger.log('MeiliSearch initialized successfully');
    } catch (error) {
      this.logger.error('Failed to initialize MeiliSearch', error);
    }
  }

  private async initializeIndex() {
    try {
      // Check if index exists
      await this.client.getIndex(this.indexName);
      this.logger.log(`Index '${this.indexName}' already exists`);
    } catch (error) {
      // Create index if it doesn't exist
      this.logger.log(`Creating index '${this.indexName}'...`);
      await this.client.createIndex(this.indexName, { primaryKey: 'id' });
    }

    // Configure index settings
    await this.configureIndexSettings();
  }

  private async configureIndexSettings() {
    const settings = {
      searchableAttributes: [
        'title',
        'description',
        'tags',
        'category',
        'condition',
      ],
      filterableAttributes: [
        'category',
        'condition',
        'originalPrice',
        'discountedPrice',
        'discount',
        'userId',
        'stock',
      ],
      sortableAttributes: [
        'originalPrice',
        'discountedPrice',
        'createdAt',
        'stock',
        'discount',
      ],
      rankingRules: [
        'words',
        'typo',
        'proximity',
        'attribute',
        'sort',
        'exactness',
      ],
    };

    await this.productsIndex.updateSettings(settings);
    this.logger.log('Index settings configured');
  }

  /**
   * Add or update a single product in the search index
   */
  async indexProduct(product: ProductDocument) {
    try {
      const task = await this.productsIndex.addDocuments([product]);
      this.logger.debug(`Product ${product.id} indexed. Task UID: ${task.taskUid}`);
      return task;
    } catch (error) {
      this.logger.error(`Failed to index product ${product.id}`, error);
      throw error;
    }
  }

  /**
   * Add or update multiple products in the search index
   */
  async indexProducts(products: ProductDocument[]) {
    try {
      const task = await this.productsIndex.addDocuments(products);
      this.logger.debug(`${products.length} products indexed. Task UID: ${task.taskUid}`);
      return task;
    } catch (error) {
      this.logger.error('Failed to index products', error);
      throw error;
    }
  }

  /**
   * Update a product in the search index
   */
  async updateProduct(product: Partial<ProductDocument> & { id: number }) {
    try {
      const task = await this.productsIndex.updateDocuments([product]);
      this.logger.debug(`Product ${product.id} updated. Task UID: ${task.taskUid}`);
      return task;
    } catch (error) {
      this.logger.error(`Failed to update product ${product.id}`, error);
      throw error;
    }
  }

  /**
   * Remove a product from the search index
   */
  async deleteProduct(productId: number) {
    try {
      const task = await this.productsIndex.deleteDocument(productId);
      this.logger.debug(`Product ${productId} deleted. Task UID: ${task.taskUid}`);
      return task;
    } catch (error) {
      this.logger.error(`Failed to delete product ${productId}`, error);
      throw error;
    }
  }

  /**
   * Search for products
   */
  async search(
    query: string,
    options?: {
      filter?: string | string[];
      sort?: string[];
      limit?: number;
      offset?: number;
      attributesToRetrieve?: string[];
      attributesToHighlight?: string[];
    },
  ) {
    try {
      const results = await this.productsIndex.search(query, {
        limit: options?.limit || 20,
        offset: options?.offset || 0,
        filter: options?.filter,
        sort: options?.sort,
        attributesToRetrieve: options?.attributesToRetrieve,
        attributesToHighlight: options?.attributesToHighlight || ['title', 'description'],
      });

      this.logger.debug(`Search query: "${query}" returned ${results.hits.length} results`);
      return results;
    } catch (error) {
      this.logger.error(`Search failed for query: "${query}"`, error);
      throw error;
    }
  }

  /**
   * Get product by ID from search index
   */
  async getProduct(productId: number) {
    try {
      return await this.productsIndex.getDocument(productId);
    } catch (error) {
      this.logger.error(`Failed to get product ${productId}`, error);
      throw error;
    }
  }

  /**
   * Get index statistics
   */
  async getStats() {
    try {
      return await this.productsIndex.getStats();
    } catch (error) {
      this.logger.error('Failed to get index stats', error);
      throw error;
    }
  }

  /**
   * Clear all products from index
   */
  async clearIndex() {
    try {
      const task = await this.productsIndex.deleteAllDocuments();
      this.logger.warn(`All products cleared from index. Task UID: ${task.taskUid}`);
      return task;
    } catch (error) {
      this.logger.error('Failed to clear index', error);
      throw error;
    }
  }

  /**
   * Sync all products from database to search index
   * Call this method from your ProductService
   */
  async syncAllProducts(products: ProductDocument[]) {
    try {
      this.logger.log(`Syncing ${products.length} products to search index...`);
      await this.clearIndex();
      await this.indexProducts(products);
      this.logger.log('Product sync completed');
    } catch (error) {
      this.logger.error('Failed to sync products', error);
      throw error;
    }
  }
}
