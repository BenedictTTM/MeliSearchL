// Example NestJS Product Service Integration
// Modify your existing: Backend/src/product/product.service.ts

import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { MeiliSearchService } from '../meilisearch/meilisearch.service';

@Injectable()
export class ProductService {
  constructor(
    private prisma: PrismaService,
    private meiliSearch: MeiliSearchService,
  ) {}

  // When creating a product
  async create(createProductDto: CreateProductDto, userId: number) {
    // 1. Create in database
    const product = await this.prisma.product.create({
      data: {
        ...createProductDto,
        userId,
      },
      include: {
        user: true,
      },
    });

    // 2. Index in MeiliSearch (async, don't block response)
    this.meiliSearch.indexProduct({
      id: product.id,
      title: product.title,
      description: product.description,
      originalPrice: product.originalPrice,
      discountedPrice: product.discountedPrice,
      discount: product.discount,
      category: product.category,
      condition: product.condition,
      tags: product.tags,
      userId: product.userId,
      stock: product.stock,
      images: product.images,
      createdAt: product.createdAt.toISOString(),
      updatedAt: product.updatedAt.toISOString(),
    }).catch(err => {
      // Log error but don't fail the request
      console.error('Failed to index product in MeiliSearch:', err);
    });

    return product;
  }

  // When updating a product
  async update(id: number, updateProductDto: UpdateProductDto, userId: number) {
    // 1. Update in database
    const product = await this.prisma.product.update({
      where: { id, userId },
      data: updateProductDto,
    });

    // 2. Update in MeiliSearch
    this.meiliSearch.updateProduct({
      id: product.id,
      ...updateProductDto,
      updatedAt: product.updatedAt.toISOString(),
    }).catch(err => {
      console.error('Failed to update product in MeiliSearch:', err);
    });

    return product;
  }

  // When deleting a product
  async remove(id: number, userId: number) {
    // 1. Delete from database
    const product = await this.prisma.product.delete({
      where: { id, userId },
    });

    // 2. Delete from MeiliSearch
    this.meiliSearch.deleteProduct(id).catch(err => {
      console.error('Failed to delete product from MeiliSearch:', err);
    });

    return product;
  }

  // Search endpoint
  async search(query: string, filters?: {
    category?: string;
    condition?: string;
    minPrice?: number;
    maxPrice?: number;
    userId?: number;
  }) {
    // Build filter string
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
    
    if (filters?.userId !== undefined) {
      filterArray.push(`userId = ${filters.userId}`);
    }

    // Search with MeiliSearch
    return await this.meiliSearch.search(query, {
      filter: filterArray.length > 0 ? filterArray : undefined,
      sort: ['discount:desc'], // Sort by discount (highest first)
      limit: 20,
    });
  }

  // Sync all products (run once or via cron job)
  async syncAllToSearch() {
    const products = await this.prisma.product.findMany({
      include: {
        user: true,
      },
    });

    const documents = products.map(product => ({
      id: product.id,
      title: product.title,
      description: product.description,
      originalPrice: product.originalPrice,
      discountedPrice: product.discountedPrice,
      discount: product.discount,
      category: product.category,
      condition: product.condition,
      tags: product.tags,
      userId: product.userId,
      stock: product.stock,
      images: product.images,
      createdAt: product.createdAt.toISOString(),
      updatedAt: product.updatedAt.toISOString(),
    }));

    await this.meiliSearch.syncAllProducts(documents);
    
    return { synced: documents.length };
  }
}
