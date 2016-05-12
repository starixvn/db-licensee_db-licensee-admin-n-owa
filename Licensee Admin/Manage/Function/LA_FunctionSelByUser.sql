USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_FunctionSelByUser]    Script Date: 9/8/2014 4:52:14 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_FunctionSelByUser]
	@UserID	 INT
AS

/*  
	 Created: 20140814@Florent
	 Task : Select Function list by User
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     
	 Params :	 @getAll : 0 : get only Function active
				    : 1 : get all function both active and not
*/
SET NOCOUNT ON

BEGIN
    SELECT	
		  f.FunctionID
		  ,FunctionName
		  ,FunctionDesc
		  ,ParentID
		  ,ParentName
		  ,URL
		  ,CreatedDate
		  ,ModifiedDate
		  ,DisplayOrder
		  ,Creator
		  ,f.StatusID AS IsActive
		  ,FunctionKey	
    FROM dbo.LA_Function f WITH(NOLOCK) 
		 INNER JOIN dbo.LA_UserFunction uf WITH(NOLOCK) ON f.FunctionID = uf.FunctionID
    WHERE uf.UserID = @UserID AND f.StatusID != 0
		  --AND (@getAll = 1 or f.StatusID != @getAll)
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_FunctionSelByUser] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_FunctionSelByUser] TO bodbAdminNet 
