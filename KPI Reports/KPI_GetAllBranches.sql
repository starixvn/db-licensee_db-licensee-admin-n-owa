USE [bodb_Licensee]
GO
/****** Object:  StoredProcedure [dbo].[KPI_GetAllBranches]    Script Date: 06/02/2014 05:15:44 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.KPI_GetAllBranches    Script Date: 3/24/2014 11:12:45  ******/
ALTER PROCEDURE [dbo].[KPI_GetAllBranches]   
	@BranchID int = 0,
	@BranchType int = -1
AS  
  
/*  
 * Created by : 20140117@Francis 
 * Task  : Get all branches for KPI report(KPI structural re-arrangement task) 
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
   - 20140324@Francis: Remove RNG Casino and Bingo restriction
 * Param's Explanation:    
 * 
 */  
 
BEGIN
	SET NOCOUNT ON  
	
	SELECT BranchID, BranchName, BranchType, OrderNo
	FROM KPI_Branches (NOLOCK)
	WHERE ((@BranchID = 0) OR (@BranchID <> 0 AND BranchID = @BranchID))
	AND ((@BranchType = -1) OR (@BranchType <> -1 AND BranchType = @BranchType))
	AND IsActive = 1
END