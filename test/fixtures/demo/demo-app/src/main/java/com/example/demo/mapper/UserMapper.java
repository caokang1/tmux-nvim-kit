package com.example.demo.mapper;

import com.example.demo.entity.User;
import java.util.List;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

@Mapper
public interface UserMapper {
    User selectById(@Param("id") Long id);

    List<User> selectAll();

    int insertUser(User user);
}
