import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;
import java.util.stream.Gatherers;

/// Annotation definitions for standalone compilation and syntax demonstration.
@interface Service {}
@interface Transactional {}
@interface Autowired {}
@interface Value {
    String value() default "";
}
@interface Nullable {}
@interface Async {}

/// Base class demonstrating Java 25 Flexible Constructor Bodies (statements before super)
class BaseOrderProcessor {
    final int timeoutMs;
    BaseOrderProcessor(int timeoutMs) { this.timeoutMs = timeoutMs; }
}

class FastOrderProcessor extends BaseOrderProcessor {
    FastOrderProcessor(int timeoutMs) {
        // Java 25 (JEP 492/513): Statements executed before super()
        if (timeoutMs < 100) {
            timeoutMs = 100;
        }
        super(timeoutMs);
    }
}

/// Order record (Java 16+ records, target for Java 21+ pattern matching deconstruction)
record OrderRecord(Long id, String customerId, double amount, Instant timestamp) {}

interface BaseService {
    Optional<sample.OrderSnapshot> findById(Long id);
}

interface OrderRepository {
    Optional<OrderRecord> findById(Long id);
    List<OrderRecord> findByCustomer(String customerId);
}

class InMemoryOrderRepository implements OrderRepository {
    private final List<OrderRecord> orders = List.of(
        new OrderRecord(1L, "cust-42", 129.50, Instant.now()),
        new OrderRecord(2L, "cust-42", 45.00, Instant.now()),
        new OrderRecord(3L, "cust-99", 250.00, Instant.now())
    );

    @Override
    public Optional<OrderRecord> findById(Long id) {
        return orders.stream().filter(o -> o.id().equals(id)).findFirst();
    }

    @Override
    public List<OrderRecord> findByCustomer(String customerId) {
        return orders.stream().filter(o -> o.customerId().equals(customerId)).toList();
    }
}

/// Service demonstrating authentic Solarized Dark highlighting in modern Java 25 LTS.
/// Showcases Markdown doc comments (///), Flexible Constructors, Stream Gatherers,
/// Record Patterns with guards, Unnamed variables (_), Sequenced Collections, and Virtual Threads.
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
                .map(order -> new OrderSnapshot(order.id(), order.customerId(), order.amount(), order.timestamp()));
    }

    /// Computes tiered discount using Pattern Matching for switch with Record Patterns and guards.
    public double computeDiscount(Object target) {
        return switch (target) {
            case OrderRecord(Long _, String _, double amount, Instant _) when amount >= 100.0 ->
                amount * 0.15;
            case OrderRecord(Long _, String _, double amount, Instant _) ->
                amount * 0.05;
            case Number n ->
                n.doubleValue() * 0.02;
            case null, default -> 0.0;
        };
    }

    /// Batches orders into windows of 2 using Java 24/25 Stream Gatherers (JEP 485).
    public List<List<OrderSnapshot>> batchOrders(List<OrderSnapshot> items) {
        return items.stream()
                .gather(Gatherers.windowFixed(2))
                .toList();
    }

    @Async
    public CompletableFuture<List<OrderSnapshot>> fetchActiveOrders(String customerId) {
        List<OrderSnapshot> orders = orderRepository.findByCustomer(customerId).stream()
                .filter(order -> order.amount() > 0.0)
                .map(o -> new OrderSnapshot(o.id(), customerId, o.amount() * TAX_RATE_MULTIPLIER, o.timestamp()))
                .toList();

        return CompletableFuture.completedFuture(orders);
    }

    @Deprecated(since = "2.1.0", forRemoval = true)
    public void processLegacyOrder(Long legacyId) {
        System.err.printf("Processing obsolete order [%d] on port %d (buffer=%d)%n", legacyId, listeningPort, DEFAULT_BUFFER_SIZE);
    }

    public static void main(String[] args) {
        sample service = new sample();
        FastOrderProcessor processor = new FastOrderProcessor(50);
        service.processLegacyOrder((long) processor.timeoutMs);

        // Sequenced Collections (Java 21): getFirst() & getLast()
        List<OrderSnapshot> snapshots = service.fetchActiveOrders("cust-42").join();
        if (!snapshots.isEmpty()) {
            OrderSnapshot first = snapshots.getFirst();
            OrderSnapshot last = snapshots.getLast();
            System.out.printf("First order [%d]: $%.2f, Last order [%d]: $%.2f%n",
                first.id(), first.totalAmount(), last.id(), last.totalAmount());
        }

        // Stream Gatherers (Java 24/25): Windowed batching
        List<List<OrderSnapshot>> batches = service.batchOrders(snapshots);
        System.out.printf("Batched %d snapshots into %d window(s)%n", snapshots.size(), batches.size());

        // Virtual Threads (Java 21) & Unnamed Variables (Java 22)
        Thread vThread = Thread.ofVirtual().name("sample-worker").start(() -> {
            service.findById(1L).ifPresent(order -> {
                double discount = service.computeDiscount(
                    new OrderRecord(order.id(), order.customerId(), order.totalAmount(), order.timestamp()));
                System.out.printf("Order [%d] for %s: $%.2f (Discount: $%.2f) on %s%n",
                    order.id(), order.customerId(), order.totalAmount(), discount, Thread.currentThread());
            });
        });

        try {
            vThread.join();
        } catch (InterruptedException _) {
            Thread.currentThread().interrupt();
        }
    }
}
