import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;

/**
 * Type declarations and annotations supporting standalone compilation.
 */
@interface Service {}
@interface Transactional {}
@interface Autowired {}
@interface Value {
    String value() default "";
}
@interface Nullable {}
@interface Async {}

record OrderRecord(Long id, String customerId, double amount) {}

interface BaseService {
    Optional<sample.OrderSnapshot> findById(Long id);
}

interface OrderRepository {
    Optional<OrderRecord> findById(Long id);
    List<OrderRecord> findByCustomer(String customerId);
}

class InMemoryOrderRepository implements OrderRepository {
    @Override
    public Optional<OrderRecord> findById(Long id) {
        return Optional.of(new OrderRecord(id, "cust-42", 99.95));
    }

    @Override
    public List<OrderRecord> findByCustomer(String customerId) {
        return List.of(new OrderRecord(1L, customerId, 150.00));
    }
}

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
    private OrderRepository orderRepository = new InMemoryOrderRepository();

    @Value("${server.port:8080}")
    private int listeningPort = 8080;

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
        System.err.printf("Processing obsolete order [%d] on port %d (buffer=%d)%n", legacyId, listeningPort, DEFAULT_BUFFER_SIZE);
    }

    public static void main(String[] args) {
        sample service = new sample();
        service.processLegacyOrder(101L);
        service.findById(1L).ifPresent(order ->
            System.out.printf("Order [%d] for %s: $%.2f at %s%n",
                order.id(), order.customerId(), order.totalAmount(), order.timestamp())
        );
    }
}
