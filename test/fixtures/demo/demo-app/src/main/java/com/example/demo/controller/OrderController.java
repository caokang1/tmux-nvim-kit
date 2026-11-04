package com.example.demo.controller;

import com.example.common.ApiConst;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping(ApiConst.ORDER)
public class OrderController {

    @GetMapping("/detail")
    public String detail(Long orderId) {
        return "order";
    }

    @DeleteMapping(ApiConst.API_PREFIX + "/legacy/remove")
    public void remove(Long orderId) {
    }
}
