package com.example.service;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;

/**
 * Service demonstrating authentic Solarized Dark highlighting in Java.
 * Showcases Spring/Jakarta annotations, generics, records, streams, and lambdas.
 */
@Service
@Transactional
public class sample implements BaseService {

    private static final int DEFAULT_BUFFER_SIZE = 1024;
    private static final double TAX_RATE_MULTIPLIER = 1.0825;

    @Autowired
    private OrderRepository orderRepository;

    @Value("${server.port:8080}")
    private int listeningPort;

    public record OrderSnapshot(Long id, String customerId, double totalAmount, Instant timestamp) {}

    @Override
    @Nullable
    public Optional<OrderSnapshot> findById(Long id) {
        if (id == null || id <= 0L) {
            throw new IllegalArgumentException("Order ID must be positive");
        }
        return orderRepository.findById(id)
                .map(order -> new OrderSnapshot(order.id(), order.customerId(), order.amount(), Instant.now()));
    }

    @Async
    public CompletableFuture<List<OrderSnapshot>> fetchActiveOrders(String customerId) {
        List<OrderSnapshot> orders = orderRepository.findByCustomer(customerId).stream()
                .filter(order -> order.amount() > 0.0)
                .map(o -> new OrderSnapshot(o.id(), customerId, o.amount() * TAX_RATE_MULTIPLIER, Instant.now()))
                .toList();

        return CompletableFuture.completedFuture(orders);
    }

    @Deprecated(since = "2.1.0", forRemoval = true)
    public void processLegacyOrder(Long legacyId) {
        System.err.printf("Processing obsolete order [%d] on port %d%n", legacyId, listeningPort);
    }
}
