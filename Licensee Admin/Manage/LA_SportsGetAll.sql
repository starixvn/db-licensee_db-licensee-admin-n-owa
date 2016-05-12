USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_SportsGetAll]    Script Date: 9/8/2014 5:07:08 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.OA_SportsGetAll    Script Date: 3/14/2012 3:11:18 PM ******/
ALTER PROCEDURE [dbo].[LA_SportsGetAll]
AS
/*    
 Created : Florent.Nguyen    
 Date : 2014-09-03  
    Task : Get all sport types  , only SportsBook
    DB  : DB052.bodb02    
    Revisions:      
*/  

BEGIN  
	SET NOCOUNT ON   

	SELECT Sporttype,SportName  
	FROM Sports WITH (NOLOCK)  
	WHERE sporttype <= 99
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_SportsGetAll] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_SportsGetAll] TO bodbAdminNet 

