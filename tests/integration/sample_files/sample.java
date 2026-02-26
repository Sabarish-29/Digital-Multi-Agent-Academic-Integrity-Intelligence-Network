/**
 * Sample Java submission for DMAIIN integration testing.
 */
public class Sample {

    /**
     * Print a greeting message.
     */
    public static void helloWorld() {
        System.out.println("Hello, World!");
    }

    /**
     * Return the sum of two integers.
     */
    public static int add(int a, int b) {
        return a + b;
    }

    /**
     * Compute the factorial of a non-negative integer.
     */
    public static long factorial(int n) {
        if (n < 0) {
            throw new IllegalArgumentException("Factorial is not defined for negative numbers");
        }
        if (n <= 1) {
            return 1;
        }
        return n * factorial(n - 1);
    }

    public static void main(String[] args) {
        helloWorld();
        System.out.println("2 + 3 = " + add(2, 3));
        System.out.println("5! = " + factorial(5));
    }
}
