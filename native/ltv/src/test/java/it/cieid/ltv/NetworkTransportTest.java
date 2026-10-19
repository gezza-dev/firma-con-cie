// SPDX-License-Identifier: BSD-3-Clause
package it.cieid.ltv;
import java.nio.file.Path;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
// Synthetic loopback proxy only. No document, CIE, trust store or system proxy.
public final class NetworkTransportTest {
 public static void main(String[] args)throws Exception {
  if(args.length!=2)throw new IllegalArgumentException("arguments");
  int port=Integer.parseInt(args[1]);if(port<1||port>65535)throw new IllegalArgumentException("port");
  byte[] config=("CIE-NETWORK-1\n1\n127.0.0.1\n"+port+"\ntest-user\ntest-pass\n").getBytes(StandardCharsets.UTF_8);
  byte[] bytes=CrlEvidence.transport(Path.of(args[0]),config).get("http://93.184.216.34/crl",4000);
  if(!Arrays.equals(bytes,"TEST".getBytes(StandardCharsets.US_ASCII)))throw new AssertionError("private proxy pipe did not reach helper");
  System.out.println("PASS shared Java CRL transport applies proxy and credentials through private stdin");
  Arrays.fill(config,(byte)0);
 }
}
