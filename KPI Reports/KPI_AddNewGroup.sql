USE [bodb_Licensee]
GO
/****** Object:  StoredProcedure [dbo].[KPI_AddNewGroup]    Script Date: 06/02/2014 05:15:25 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.KPI_AddNewGroup    Script Date: 3/3/2014 10:09:27  ******/

ALTER PROCEDURE [dbo].[KPI_AddNewGroup]   
	@GroupName varchar(50) = NULL,
	@BranchID int = 0,
	@GroupType int = 1,
	@SiteID int = NULL,
	@OrderNo int = 0,
	@RelatedBranch varchar(50) = '',
	@IsActive bit = 0,
	@ProductID int = 0
AS  
  
/*  
 * Created by : 20140225@Francis 
 * Task  : Add new Group into KPI report(KPI structural re-arrangement task) 
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
   - 20140302@Francis: Fix not actived in SystemLicensee table bug
 * Param's Explanation:    
 * - @SiteID: LicenseeID
 */  
BEGIN
declare @intCount int = 0
select @intCount = COUNT(1)
from KPI_Branches with (NOLOCK)
where BranchID = @BranchID

IF @GroupName IS NOT NULL AND @intCount > 0 AND @GroupName <> ''
	BEGIN
		
		declare @TempID int = 0
		
		select @TempID = GroupID
		FROM KPI_Groups (NOLOCK)
		WHERE GroupName = @GroupName
		
		IF @TempID = 0--new group case
		BEGIN
		
			SET XACT_ABORT ON
			BEGIN TRAN
				INSERT INTO KPI_Groups (GroupName, GroupType, SiteID, OrderNo, RelatedBranch, IsActive)
				SELECT @GroupName, @GroupType, @SiteID, @OrderNo, @RelatedBranch, @IsActive
			
				set @TempID = (SELECT MAX(GroupID) FROM KPI_Groups WITH (NOLOCK))
	
				insert into KPI_BranchGroup (BranchID, GroupID, ProductID)
				SELECT @BranchID, @TempID, @ProductID	
			COMMIT
		END
		ELSE--existing group case
		BEGIN
			
			set @intCount = 0
			
			select @intCount = COUNT(1)
			from KPI_BranchGroup with (NOLOCK)
			where BranchID = @BranchID and GroupID = @TempID and ProductID = @ProductID
			
			IF @intCount = 0
			BEGIN
				insert INTO KPI_BranchGroup(BranchID, GroupID, ProductID)
				select @BranchID, @TempID, @ProductID
			END
		END
	
		IF @SiteID IS NOT NULL
		BEGIN
			DECLARE @SystemID int
			SELECT @SystemID = id
			FROM Systems WITH (NOLOCK)
			WHERE SystemName = 'KPI'
			
			UPDATE SystemLicensee WITH (UPDLOCK,ROWLOCK)
			SET IsActive = 1
			WHERE SystemID = @SystemID
			AND LicenseeID = @SiteID
			AND IsActive = 0
		END
	
	END
ELSE
	PRINT 'Invalid GroupName or BranchID'

END