///
/// Copyright © 2024, Kanton Bern
/// All rights reserved.
///
/// Redistribution and use in source and binary forms, with or without
/// modification, are permitted provided that the following conditions are met:
///     * Redistributions of source code must retain the above copyright
///       notice, this list of conditions and the following disclaimer.
///     * Redistributions in binary form must reproduce the above copyright
///       notice, this list of conditions and the following disclaimer in the
///       documentation and/or other materials provided with the distribution.
///     * Neither the name of the <organization> nor the
///       names of its contributors may be used to endorse or promote products
///       derived from this software without specific prior written permission.
///
/// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
/// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
/// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
/// DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
/// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
/// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
/// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
/// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
/// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
/// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
///

import {Component, NgModule, OnDestroy, OnInit} from '@angular/core';
import {Store} from "@ngrx/store";
import {AppState} from "../../../store/app/app.state";
import {debounceTime, distinctUntilChanged, Observable, Subject, Subscription} from "rxjs";
import {selectUsers} from "../../../store/users-management/users-management.selector";
import {CommonModule} from "@angular/common";
import {AdUser, CreateUserForm, User, UserAction} from "../../../store/users-management/users-management.model";
import {FormBuilder, FormGroup, FormsModule, ReactiveFormsModule, Validators} from "@angular/forms";
import {UserEditComponent} from "./user-edit/user-edit.component";
import {ActionsUserPopupComponent} from "./actions-user-popup/actions-user-popup.component";
import {TranslocoModule} from "@ngneat/transloco";
import {RouterLink} from "@angular/router";
import {TableModule} from "primeng/table";
import {TagModule} from "primeng/tag";
import {TooltipModule} from "primeng/tooltip";
import {InputTextModule} from "primeng/inputtext";
import {ButtonModule} from "primeng/button";
import {ToolbarModule} from "primeng/toolbar";
import {EditorModule} from "primeng/editor";
import {RippleModule} from "primeng/ripple";
import {ConfirmDialogModule} from "primeng/confirmdialog";
import {StyleClassModule} from "primeng/styleclass";
import {TabViewModule} from "primeng/tabview";
import {AutoCompleteModule} from "primeng/autocomplete";
import {CheckboxModule} from "primeng/checkbox";
import {DividerModule} from "primeng/divider";
import {map, switchMap} from "rxjs/operators";
import {DropdownModule} from "primeng/dropdown";
import {DashboardViewerPermissionsComponent} from "./user-edit/dashboard-viewer-permissions/dashboard-viewer-permissions.component";
import {MultiSelectModule} from "primeng/multiselect";
import {naviElements} from "../../../app-navi-elements";
import {UsersManagementService} from "../../../store/users-management/users-management.service";
import {BaseComponent} from "../../../shared/components/base/base.component";
import {createBreadcrumbs} from "../../../store/breadcrumb/breadcrumb.action";
import {createUser, loadUsers, navigateToUserEdition, showUserActionPopup, syncUsers} from "../../../store/users-management/users-management.action";

@Component({
  selector: 'app-user-management',
  templateUrl: './user-management.component.html',
  styleUrls: ['./user-management.component.scss']
})
export class UserManagementComponent extends BaseComponent implements OnInit, OnDestroy {

  users$: Observable<any>;
  inviteForm!: FormGroup;
  suggestedAdUsers: AdUser[] = [];
  private searchSubscription?: Subscription;
  private readonly searchSubject = new Subject<string | undefined>();

  constructor(private store: Store<AppState>, private fb: FormBuilder, private userService: UsersManagementService) {
    super();
    this.users$ = this.store.select(selectUsers).pipe(map(d => [...d]));
    this.store.dispatch(loadUsers());
    this.store.dispatch(createBreadcrumbs({
      breadcrumbs: [
        {
          label: naviElements.userManagement.label,
          routerLink: naviElements.userManagement.path,
        }
      ]
    }));

    this.searchSubscription = this.searchSubject
      .pipe(
        debounceTime(500),
        distinctUntilChanged(),
        switchMap((searchQuery: string | undefined) => {
          return this.userService.searchUserByEmail(searchQuery);
        })
      )
      .subscribe(
        (users: AdUser[]) => {
          return this.suggestedAdUsers = this.enhanceSuggestedAdUsers(users);
        }
      )
  }

  override ngOnInit(): void {
    super.ngOnInit();
    this.inviteForm = this.fb.group({
      user: [null, Validators.compose([Validators.required.bind(this), Validators.email.bind(this)])],
      firstName: [null, Validators.compose([Validators.required.bind(this), Validators.minLength(3), Validators.maxLength(255), Validators.pattern(/[\p{L}\p{N}].*/u)])],
      lastName: [null, Validators.compose([Validators.required.bind(this), Validators.minLength(3), Validators.maxLength(255), Validators.pattern(/[\p{L}\p{N}].*/u)])],
    });
  }

  public ngOnDestroy(): void {
    this.searchSubscription?.unsubscribe();
  }

  createUser() {
    if (this.inviteForm.valid) {
      const inviteFormData = this.inviteForm.getRawValue() as CreateUserForm;
      this.store.dispatch(createUser({createUserForm: inviteFormData}));
      this.inviteForm.reset();
    }
  }

  editUser(data: User) {
    this.store.dispatch(navigateToUserEdition({userId: data.id}));
  }

  showUserDeletionPopup(data: User) {
    this.store.dispatch(showUserActionPopup({userActionForPopup: {user: data, action: UserAction.DELETE, actionFromUsersEdition: false}}));
  }

  enableUser(data: User) {
    this.store.dispatch(showUserActionPopup({userActionForPopup: {user: data, action: UserAction.ENABLE, actionFromUsersEdition: false}}));
  }

  disableUser(data: User) {
    this.store.dispatch(showUserActionPopup({userActionForPopup: {user: data, action: UserAction.DISABLE, actionFromUsersEdition: false}}));
  }

  syncUsers() {
    this.store.dispatch(syncUsers());
  }

  filterMails($event: any) {
    const searchQuery = $event.query;
    this.searchSubject.next(searchQuery?.trim());
    this.inviteForm.get('firstName')?.reset();
    this.inviteForm.get('lastName')?.reset();
  }

  onSelectEmail($event: any) {
    this.inviteForm.get('firstName')?.setValue($event.firstName);
    this.inviteForm.get('lastName')?.setValue($event.lastName);
    this.inviteForm.get('user')?.setErrors(null);
  }

  private enhanceSuggestedAdUsers(users: AdUser[]) {
    return users.map(user => {
      user.label = user.email + " (" + user.firstName + " " + user.lastName + ")";
      return user;
    });
  }
}

@NgModule({
  imports: [
    CommonModule,
    ReactiveFormsModule,
    TranslocoModule,
    RouterLink,
    TableModule,
    TagModule,
    TooltipModule,
    InputTextModule,
    ButtonModule,
    ToolbarModule,
    EditorModule,
    RippleModule,
    FormsModule,
    ConfirmDialogModule,
    StyleClassModule,
    TabViewModule,
    AutoCompleteModule,
    CheckboxModule,
    DividerModule,
    DropdownModule,
    MultiSelectModule
  ],
  declarations: [
    UserManagementComponent,
    UserEditComponent,
    ActionsUserPopupComponent,
    DashboardViewerPermissionsComponent
  ],
  exports: [UserManagementComponent]
})
export class UserManagementModule {
}
