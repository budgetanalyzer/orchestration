# Persistence Layer Architecture

## Overview

This document outlines the architectural principles and guidelines for the persistence layer across all Budget Analyzer microservices.

## Core Principle: Pure JPA, No Hibernate

### Rationale

We use **pure JPA (Jakarta Persistence API)** exclusively and avoid Hibernate-specific features to prevent vendor lock-in.

**Why avoid Hibernate-specific features?**
- **Portability**: Pure JPA allows switching JPA providers (EclipseLink, OpenJPA, etc.) without code changes
- **Standard compliance**: JPA is a specification with multiple implementations
- **Future flexibility**: While Hibernate is unlikely to be replaced, architectural discipline maintains our options

**Acknowledgment**: We recognize that Hibernate is the most mature and widely-used JPA implementation, and a migration away from it is highly unlikely. However, adhering to the JPA standard is a best practice that costs us nothing while maintaining architectural flexibility.

## Rules and Guidelines

### Import Restrictions

**RULE**: No Hibernate-specific imports anywhere in the codebase.

❌ **Forbidden**:
```java
import org.hibernate.*;
import org.hibernate.annotations.*;
import org.hibernate.criterion.*;
```

✅ **Allowed**:
```java
import jakarta.persistence.*;
```

### Enforcement

This rule can be enforced using **Checkstyle**:

```xml
<module name="IllegalImport">
    <property name="illegalPkgs" value="org.hibernate"/>
    <property name="illegalClasses" value=""/>
    <message key="import.illegal"
             value="Hibernate-specific imports are forbidden. Use JPA (jakarta.persistence.*) instead to avoid vendor lock-in."/>
</module>
```

Adding this to your `checkstyle.xml` configuration will fail the build if any Hibernate imports are detected.

**Alternative: ArchUnit** for architectural testing:
```java
@Test
void shouldNotImportHibernate() {
    noClasses()
        .should().dependOnClassesThat().resideInAPackage("org.hibernate..")
        .check(new ClassFileImporter().importPackages("com.yourpackage.."));
}
```

## JPA Entity Design Guidelines

*(To be documented)*

## Database Schema Rules

*(To be documented)*

## Transaction Management

*(To be documented)*

## Repository Pattern

*(To be documented)*
