// SPDX-License-Identifier: BSD-3-Clause
package it.cieid.ltv;
import org.junit.jupiter.api.Test;
class WorkerTest {
    @Test void archivalValidation() throws Exception { LtvSelfTest.main(new String[]{System.getProperty("user.dir")+"/../../.build/ltv-test-fixtures"}); }
}
