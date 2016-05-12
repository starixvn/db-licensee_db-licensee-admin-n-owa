USE [bodb02]
GO

/****** Object:  StoredProcedure [dbo].[LA_KenoBetTypesGetAll]    Script Date: 06/03/2015 14:59:48 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/****** Object:  Stored Procedure dbo.LA_KenoBetTypesGetAll    Script Date: 06/03/2015 10:26:13 AM ******/
CREATE PROCEDURE [dbo].[LA_KenoBetTypesGetAll]	
AS
/*    
	Created : FLorent	    
	Date : 2015-03-04  
    Task : Get all Keno bettypes      
    DB  : DB052.bodb02         
    Revisions:
	
*/  

BEGIN  
	SET NOCOUNT ON   
	SELECT DISTINCT b.BettypeID AS Bettype, b.BettypeName
	FROM dbo.View_KenoBettypeMapping b			
	ORDER BY b.BettypeID	
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_KenoBetTypesGetAll] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_KenoBetTypesGetAll] TO bodbAdminNet 


