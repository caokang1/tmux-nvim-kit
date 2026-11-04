package com.example.demo.entity;

import com.example.common.BaseEntity;
import lombok.Data;

@Data
public class User extends BaseEntity {
    private String name;
    private Integer age;

    @Override
    public String displayName() {
        return name + "(" + age + ")";
    }
}
